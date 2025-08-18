//
//  EnhancedInvoke.swift
//  Escrow Buddy
//
//  Copyright 2025 Escrow Buddy Enhanced
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreFoundation
import Foundation
import Security
import os.log

class EnhancedInvoke: EBMechanism {
    private static let log = OSLog(subsystem: "com.netflix.Escrow-Buddy", category: "EnhancedInvoke")
    fileprivate let bundleid = "com.netflix.Escrow-Buddy"
    
    // Bridge to Objective-C managers
    private let rotationManager = RotationManager.shared()
    private let configManager = ConfigurationManager.shared()
    private let lifecycleTracker = KeyLifecycleTracker.shared()
    
    @objc func run() {
        os_log("Starting Escrow Buddy Enhanced:Invoke", log: EnhancedInvoke.log, type: .default)
        
        // Load latest configuration
        configManager.reloadConfiguration()
        
        // Get FileVault status
        let fdestatus = getFVEnabled()
        let fvEnabled: Bool = fdestatus.encrypted
        let decrypting: Bool = fdestatus.decrypting
        
        // No action needed if FileVault is off or decrypting
        if decrypting {
            os_log("FileVault is decrypting", log: EnhancedInvoke.log, type: .default)
            allowLogin()
            return
        }
        if !fvEnabled {
            os_log("FileVault is not enabled", log: EnhancedInvoke.log, type: .default)
            allowLogin()
            return
        }
        
        // Check for FileVault escrow profile
        let escrowInfo = getFVEscrowInfo()
        let escrowLocation = escrowInfo.location
        let escrowForced = escrowInfo.forced
        
        // Guard against triggering key generation without a valid escrow profile
        if !escrowForced {
            os_log("ERROR: No MDM profile for enforcing FileVault escrow is present.",
                  log: EnhancedInvoke.log, type: .error)
            allowLogin()
            return
        } else {
            os_log("FileVault configured to escrow to: %{public}@", 
                  log: EnhancedInvoke.log, type: .default, escrowLocation)
        }
        
        // Check if rotation is needed using enhanced logic
        let shouldRotate = evaluateRotationNeed()
        
        if !shouldRotate {
            os_log("No key rotation needed at this time", log: EnhancedInvoke.log, type: .default)
            
            // Check for expiration warnings
            if shouldSendExpirationWarning() {
                sendKeyExpirationNotification()
            }
            
            allowLogin()
            return
        }
        
        // Determine rotation reason
        let rotationReason = rotationManager.getRotationReason()
        let reasonString = getRotationReasonString(rotationReason)
        
        os_log("Key rotation triggered. Reason: %{public}@", 
              log: EnhancedInvoke.log, type: .default, reasonString)
        
        // Check minimum key age restriction
        if !checkMinimumKeyAge() {
            os_log("Key has not met minimum age requirement", log: EnhancedInvoke.log, type: .default)
            allowLogin()
            return
        }
        
        // Instantiate dictionary with credentials
        guard let username = self.username else {
            os_log("Unable to instantiate username", log: EnhancedInvoke.log, type: .error)
            allowLogin()
            return
        }
        guard let password = self.password else {
            os_log("Unable to instantiate password", log: EnhancedInvoke.log, type: .error)
            allowLogin()
            return
        }
        
        let the_settings = NSDictionary.init(dictionary: [
            "Username": username, 
            "Password": password,
        ])
        
        // Generate new recovery key
        os_log("Generating a new FileVault personal recovery key", 
              log: EnhancedInvoke.log, type: .default)
        
        let newKeyID = UUID().uuidString
        
        do {
            try _ = rotateRecoveryKey(the_settings)
            
            // Record successful rotation
            lifecycleTracker.rotateKey(newKeyID, reason: reasonString)
            rotationManager.recordRotation(rotationReason)
            
            // Mark key as escrowed
            lifecycleTracker.markKeyAsEscrowed(newKeyID, location: escrowLocation)
            
            // Clear manual rotation flag if set
            if rotationManager.hasManualRotationFlag() {
                rotationManager.clearManualRotationFlag()
            }
            
            // Send success notification if enabled
            if configManager.notifyOnRotationSuccess {
                sendRotationSuccessNotification(reason: reasonString)
            }
            
            os_log("Key rotation completed successfully", log: EnhancedInvoke.log, type: .default)
            
        } catch let error as NSError {
            os_log("Caught error trying to generate a new key: %{public}@", 
                  log: EnhancedInvoke.log, type: .error, error.localizedDescription)
            
            // Send failure notification if enabled
            if configManager.notifyOnRotationFailure {
                sendRotationFailureNotification(error: error.localizedDescription)
            }
        }
        
        // Cleanup after key generation
        os_log("Setting GenerateNewKey to False to avoid multiple generations",
              log: EnhancedInvoke.log, type: .default)
        CFPreferencesSetValue(
            "GenerateNewKey" as CFString, false as CFPropertyList, bundleid as CFString,
            kCFPreferencesAnyUser, kCFPreferencesAnyHost)
        CFPreferencesSetAppValue("GenerateNewKey" as CFString, nil, bundleid as CFString)
        
        // Perform maintenance if needed
        performMaintenanceTasks()
        
        allowLogin()
        return
    }
    
    // MARK: - Enhanced Rotation Logic
    
    private func evaluateRotationNeed() -> Bool {
        // Check legacy GenerateNewKey flag first for backward compatibility
        let genKey = getGenerateNewKey()
        if genKey.generateKey && !genKey.forcedKey {
            os_log("Legacy GenerateNewKey flag is set", log: EnhancedInvoke.log, type: .default)
            return true
        }
        
        // Use enhanced rotation logic
        return rotationManager.shouldRotateKey()
    }
    
    private func checkMinimumKeyAge() -> Bool {
        let currentAge = lifecycleTracker.getCurrentKeyAgeDays()
        let minimumAge = configManager.minimumKeyAge
        
        if currentAge < minimumAge {
            os_log("Current key age (%ld days) is less than minimum (%ld days)",
                  log: EnhancedInvoke.log, type: .default, currentAge, minimumAge)
            return false
        }
        
        return true
    }
    
    private func shouldSendExpirationWarning() -> Bool {
        guard configManager.enableNotifications else { return false }
        
        let daysBeforeWarning = configManager.notificationDaysBefore
        let maxAge = configManager.maxKeyAge
        let daysUntilExpiration = lifecycleTracker.getDaysUntilExpiration(maxAge)
        
        return daysUntilExpiration <= daysBeforeWarning && daysUntilExpiration > 0
    }
    
    // MARK: - Helper Methods
    
    private func getRotationReasonString(_ reason: Int) -> String {
        switch reason {
        case 1: return "Age-based rotation"
        case 2: return "Key was used for recovery"
        case 3: return "Compliance requirement"
        case 4: return "Manual rotation requested"
        case 5: return "Scheduled rotation"
        default: return "Unknown reason"
        }
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
    
    // MARK: - Notification Methods
    
    private func sendKeyExpirationNotification() {
        let daysRemaining = lifecycleTracker.getDaysUntilExpiration(configManager.maxKeyAge)
        os_log("Sending key expiration warning: %ld days remaining", 
              log: EnhancedInvoke.log, type: .default, daysRemaining)
        // Notification implementation would go here
    }
    
    private func sendRotationSuccessNotification(reason: String) {
        os_log("Sending rotation success notification", log: EnhancedInvoke.log, type: .default)
        // Notification implementation would go here
    }
    
    private func sendRotationFailureNotification(error: String) {
        os_log("Sending rotation failure notification", log: EnhancedInvoke.log, type: .default)
        // Notification implementation would go here
    }
    
    // MARK: - Maintenance
    
    private func performMaintenanceTasks() {
        // Clean up old events periodically
        let lastMaintenance = UserDefaults.standard.object(forKey: "LastMaintenanceDate") as? Date
        let shouldPerformMaintenance = lastMaintenance == nil || 
            Date().timeIntervalSince(lastMaintenance!) > 86400 * 7 // Weekly
        
        if shouldPerformMaintenance {
            os_log("Performing maintenance tasks", log: EnhancedInvoke.log, type: .default)
            lifecycleTracker.performMaintenance()
            UserDefaults.standard.set(Date(), forKey: "LastMaintenanceDate")
        }
    }
    
    // MARK: - FileVault Operations
    
    enum FileVaultError: Error {
        case fdeSetupFailed(retCode: Int32)
        case outputPlistNull
        case outputPlistMalformed
    }
    
    func rotateRecoveryKey(_ theSettings: NSDictionary) throws -> Bool {
        os_log("rotateRecoveryKey called", log: EnhancedInvoke.log, type: .default)
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
            os_log("ERROR: fdesetup terminated with a non-zero exit status: %{public}@",
                  log: EnhancedInvoke.log, type: .error, termstatus)
            os_log("fdesetup Standard Error: %{public}@", log: EnhancedInvoke.log, type: .error,
                  String(describing: errorMessage))
            throw FileVaultError.fdeSetupFailed(retCode: task.terminationStatus)
        }
        os_log("rotateRecoveryKey succeeded", log: EnhancedInvoke.log, type: .default)
        return true
    }
}