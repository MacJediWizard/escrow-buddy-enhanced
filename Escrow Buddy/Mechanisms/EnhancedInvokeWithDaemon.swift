//
//  EnhancedInvokeWithDaemon.swift
//  Escrow Buddy Enhanced
//
//  Modified version that coordinates with background daemon
//

import CoreFoundation
import Foundation
import Security
import os.log

class EnhancedInvokeWithDaemon: EBMechanism {
    private static let log = OSLog(subsystem: "com.netflix.Escrow-Buddy", category: "EnhancedInvokeWithDaemon")
    fileprivate let bundleid = "com.netflix.Escrow-Buddy"
    
    // Bridge to Objective-C managers and XPC client
    private let rotationManager = RotationManager.shared()
    private let configManager = ConfigurationManager.shared()
    private let lifecycleTracker = KeyLifecycleTracker.shared()
    private let xpcClient = EscrowBuddyXPCClient.shared()
    
    @objc func run() {
        os_log("Starting Escrow Buddy Enhanced with Daemon Coordination", log: EnhancedInvokeWithDaemon.log, type: .default)
        
        // Notify daemon of login
        if let username = self.username {
            xpcClient.notifyLogin(forUser: username)
        }
        
        // Check if daemon is handling rotation
        if xpcClient.shouldAuthPluginRotate() == false {
            os_log("Daemon is handling rotation, skipping plugin rotation", log: EnhancedInvokeWithDaemon.log, type: .default)
            allowLogin()
            return
        }
        
        // Get FileVault status
        let fdestatus = getFVEnabled()
        let fvEnabled: Bool = fdestatus.encrypted
        let decrypting: Bool = fdestatus.decrypting
        
        // No action needed if FileVault is off or decrypting
        if decrypting {
            os_log("FileVault is decrypting", log: EnhancedInvokeWithDaemon.log, type: .default)
            allowLogin()
            return
        }
        if !fvEnabled {
            os_log("FileVault is not enabled", log: EnhancedInvokeWithDaemon.log, type: .default)
            allowLogin()
            return
        }
        
        // Check for FileVault escrow profile
        let escrowInfo = getFVEscrowInfo()
        let escrowLocation = escrowInfo.location
        let escrowForced = escrowInfo.forced
        
        if !escrowForced {
            os_log("ERROR: No MDM profile for enforcing FileVault escrow is present.",
                  log: EnhancedInvokeWithDaemon.log, type: .error)
            allowLogin()
            return
        }
        
        // Check if rotation is needed (only if daemon isn't handling it)
        let shouldRotate = evaluateRotationNeed()
        
        if !shouldRotate {
            os_log("No key rotation needed at this time", log: EnhancedInvokeWithDaemon.log, type: .default)
            allowLogin()
            return
        }
        
        // Perform rotation during login
        os_log("Performing key rotation during login", log: EnhancedInvokeWithDaemon.log, type: .default)
        
        guard let username = self.username else {
            os_log("Unable to instantiate username", log: EnhancedInvokeWithDaemon.log, type: .error)
            allowLogin()
            return
        }
        guard let password = self.password else {
            os_log("Unable to instantiate password", log: EnhancedInvokeWithDaemon.log, type: .error)
            allowLogin()
            return
        }
        
        let the_settings = NSDictionary.init(dictionary: [
            "Username": username, 
            "Password": password,
        ])
        
        let newKeyID = UUID().uuidString
        
        do {
            try _ = rotateRecoveryKey(the_settings)
            
            // Notify daemon that plugin performed rotation
            let rotationInfo: [String: Any] = [
                "keyID": newKeyID,
                "timestamp": Date(),
                "rotatedBy": "authPlugin",
                "user": username
            ]
            xpcClient.notifyPluginRotatedKey(rotationInfo)
            
            // Record rotation
            lifecycleTracker.rotateKey(newKeyID, reason: "Login-triggered rotation")
            
            os_log("Key rotation completed successfully during login", log: EnhancedInvokeWithDaemon.log, type: .default)
            
        } catch let error as NSError {
            os_log("Failed to rotate key during login: %{public}@", 
                  log: EnhancedInvokeWithDaemon.log, type: .error, error.localizedDescription)
        }
        
        // Clear manual rotation flag
        CFPreferencesSetValue(
            "GenerateNewKey" as CFString, false as CFPropertyList, bundleid as CFString,
            kCFPreferencesAnyUser, kCFPreferencesAnyHost)
        
        allowLogin()
        return
    }
    
    private func evaluateRotationNeed() -> Bool {
        // Check legacy GenerateNewKey flag first
        let genKey = getGenerateNewKey()
        if genKey.generateKey && !genKey.forcedKey {
            return true
        }
        
        // Only check rotation if daemon isn't available
        if !xpcClient.isConnected() {
            return rotationManager.shouldRotateKey()
        }
        
        return false
    }
    
    private func getGenerateNewKey() -> (generateKey: Bool, forcedKey: Bool) {
        let forcedKey: Bool = CFPreferencesAppValueIsForced(
            "GenerateNewKey" as CFString, bundleid as CFString)
        guard
            let genkey: Bool = CFPreferencesCopyAppValue(
                "GenerateNewKey" as CFString, bundleid as CFString) as? Bool
        else { return (false, forcedKey) }
        return (genkey, forcedKey)
    }
    
    enum FileVaultError: Error {
        case fdeSetupFailed(retCode: Int32)
        case outputPlistNull
        case outputPlistMalformed
    }
    
    func rotateRecoveryKey(_ theSettings: NSDictionary) throws -> Bool {
        os_log("rotateRecoveryKey called", log: EnhancedInvokeWithDaemon.log, type: .default)
        let inputPlist = try PropertyListSerialization.data(
            fromPropertyList: theSettings,
            format: PropertyListSerialization.PropertyListFormat.xml, options: 0)
        
        let inPipe = Pipe.init()
        let outPipe = Pipe.init()
        let errorPipe = Pipe.init()
        
        let task = Process.init()
        task.launchPath = "/usr/bin/fdesetup"
        task.arguments = ["changerecovery", "-personal", "-inputplist"]
        task.standardInput = inPipe
        task.standardOutput = outPipe
        task.standardError = errorPipe
        task.launch()
        inPipe.fileHandleForWriting.write(inputPlist)
        inPipe.fileHandleForWriting.closeFile()
        task.waitUntilExit()
        
        let errorOut = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorMessage = String(data: errorOut, encoding: .utf8)
        errorPipe.fileHandleForReading.closeFile()
        
        if task.terminationStatus != 0 {
            let termstatus = String(describing: task.terminationStatus)
            os_log("ERROR: fdesetup terminated with exit status: %{public}@",
                  log: EnhancedInvokeWithDaemon.log, type: .error, termstatus)
            os_log("fdesetup error: %{public}@", log: EnhancedInvokeWithDaemon.log, type: .error,
                  String(describing: errorMessage))
            throw FileVaultError.fdeSetupFailed(retCode: task.terminationStatus)
        }
        os_log("rotateRecoveryKey succeeded", log: EnhancedInvokeWithDaemon.log, type: .default)
        return true
    }
}