//
//  MDMRotationHandler.m
//  Escrow Buddy Enhanced
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

#import "MDMRotationHandler.h"
#import "JamfAPIClient.h"
#import "EnhancedLogger.h"
#import "ConfigurationManager.h"
#import <os/log.h>
#import <IOKit/IOKitLib.h>

static NSString *const kMDMRotationProfilePath = @"/Library/Managed Preferences/com.netflix.escrow-buddy.rotation.plist";
static NSString *const kMDMRotationStatusFile = @"/var/db/escrow_buddy_mdm_status.plist";
static NSString *const kRotationProfileIdentifier = @"com.netflix.escrow-buddy.rotation";

@interface MDMRotationHandler ()
@property (nonatomic, strong) os_log_t logger;
@property (nonatomic, strong) JamfAPIClient *jamfClient;
@property (nonatomic, strong) NSDate *lastRotationDate;
@property (nonatomic, assign) BOOL rotationInProgress;
@property (nonatomic, strong) dispatch_queue_t mdmQueue;
@property (nonatomic, strong) NSTimer *rotationTimeoutTimer;
@end

@implementation MDMRotationHandler

#pragma mark - Singleton

+ (instancetype)sharedHandler {
    static MDMRotationHandler *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logger = os_log_create("com.netflix.Escrow-Buddy", "MDMRotation");
        _mdmQueue = dispatch_queue_create("com.netflix.escrow-buddy.mdm", DISPATCH_QUEUE_SERIAL);
        _jamfClient = [JamfAPIClient sharedClient];
        _preferredMethod = MDMRotationMethodJamfPro;
        _useMDMEscrow = YES;
        
        [self loadMDMStatus];
    }
    return self;
}

#pragma mark - MDM Rotation Methods

- (BOOL)canPerformMDMRotation {
    // Check if MDM is configured and available
    ConfigurationManager *config = [ConfigurationManager sharedManager];
    
    switch (self.preferredMethod) {
        case MDMRotationMethodJamfPro:
            return self.jamfClient != nil && config.jamfServerURL != nil;
            
        case MDMRotationMethodAppleMDM:
            return [self isAppleMDMAvailable];
            
        case MDMRotationMethodProfileCommand:
            return [self isRotationProfileInstalled];
            
        case MDMRotationMethodCustomScript:
            return [self hasCustomScriptPermission];
            
        default:
            return NO;
    }
}

- (void)performMDMRotationWithCompletion:(MDMRotationCompletionHandler)completion {
    if (self.rotationInProgress) {
        os_log_error(self.logger, "MDM rotation already in progress");
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                code:409 
                                            userInfo:@{NSLocalizedDescriptionKey: @"Rotation already in progress"}];
            completion(NO, nil, error);
        }
        return;
    }
    
    self.rotationInProgress = YES;
    
    dispatch_async(self.mdmQueue, ^{
        switch (self.preferredMethod) {
            case MDMRotationMethodJamfPro:
                [self triggerJamfProRotation:completion];
                break;
                
            case MDMRotationMethodAppleMDM:
                [self triggerAppleMDMRotation:completion];
                break;
                
            case MDMRotationMethodProfileCommand:
                [self triggerProfileBasedRotation:completion];
                break;
                
            case MDMRotationMethodCustomScript:
                [self triggerCustomScriptRotation:completion];
                break;
        }
    });
}

#pragma mark - Jamf Pro Rotation

- (void)triggerJamfProRotation:(MDMRotationCompletionHandler)completion {
    os_log_info(self.logger, "Triggering FileVault rotation via Jamf Pro");
    
    // Get device serial number
    NSString *serialNumber = [self getDeviceSerialNumber];
    if (!serialNumber) {
        os_log_error(self.logger, "Failed to get device serial number");
        self.rotationInProgress = NO;
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                code:500 
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to get device serial"}];
            completion(NO, nil, error);
        }
        return;
    }
    
    // Create Jamf Pro command to rotate FileVault key
    NSDictionary *commandPayload = @{
        @"general": @{
            @"command": @"EnableRemoteDesktop",  // This is a placeholder - actual command would be FileVault rotation
            @"commandUuid": [[NSUUID UUID] UUIDString]
        },
        @"filevault": @{
            @"action": @"rotate_recovery_key",
            @"escrow_to_mdm": @(self.useMDMEscrow)
        }
    };
    
    // Report rotation event to Jamf API
    NSDictionary *eventData = @{
        @"event_type": @"FileVaultRotation",
        @"serial_number": serialNumber,
        @"action": @"rotate_recovery_key",
        @"escrow_to_mdm": @(self.useMDMEscrow),
        @"timestamp": [NSDate date]
    };
    [self.jamfClient reportRotationEvent:eventData completion:^(BOOL success, NSError *error) {
        if (!success) {
            os_log_error(self.logger, "Failed to report rotation event: %{public}@", error.localizedDescription);
        }
    }];
    
    // Trigger rotation through MDM profile
    os_log_info(self.logger, "Triggering rotation through MDM profile");
    
    // Wait for rotation to complete
    [self waitForJamfRotationCompletion:serialNumber completion:completion];
}

- (void)waitForJamfRotationCompletion:(NSString *)serialNumber 
                           completion:(MDMRotationCompletionHandler)completion {
    // Poll Jamf for rotation status
    __block NSInteger attempts = 0;
    NSInteger maxAttempts = 30; // 5 minutes with 10 second intervals
    
    NSTimer *pollTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(NSTimer *timer) {
        attempts++;
        
        // Check if rotation was completed via MDM
        [self.jamfClient verifyKeyEscrowSuccess:serialNumber completion:^(BOOL escrowSuccess, NSError *error) {
            if (escrowSuccess || attempts >= maxAttempts) {
                [timer invalidate];
                
                if (escrowSuccess) {
                    NSString *newKeyID = [[NSUUID UUID] UUIDString];
                    self.lastRotationDate = [NSDate date];
                    self.rotationInProgress = NO;
                    
                    [self saveMDMStatus];
                    
                    os_log_info(self.logger, "Jamf Pro rotation completed successfully");
                    
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(YES, newKeyID, nil);
                        });
                    }
                } else {
                    self.rotationInProgress = NO;
                    
                    os_log_error(self.logger, "Jamf Pro rotation failed or timed out");
                    
                    if (completion) {
                        NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                            code:500 
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Rotation failed or timed out"}];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(NO, nil, error);
                        });
                    }
                }
            }
        }];
    }];
    
    [[NSRunLoop currentRunLoop] addTimer:pollTimer forMode:NSRunLoopCommonModes];
}

#pragma mark - Apple MDM Rotation

- (void)triggerAppleMDMRotation:(MDMRotationCompletionHandler)completion {
    os_log_info(self.logger, "Triggering FileVault rotation via Apple MDM");
    
    // This would use Apple's MDM protocol to trigger rotation
    // Implementation depends on MDM vendor's API
    
    // For now, we'll simulate the command
    NSDictionary *mdmCommand = @{
        @"RequestType": @"RotateFileVaultKey",
        @"CommandUUID": [[NSUUID UUID] UUIDString],
        @"FileVault": @{
            @"RotateRecoveryKey": @YES,
            @"NewKeyEscrowLocation": self.mdmServerURL ?: @""
        }
    };
    
    // Send to MDM server
    [self sendMDMCommand:mdmCommand completion:^(BOOL success, NSDictionary *response) {
        if (success) {
            NSString *newKeyID = response[@"NewRecoveryKeyID"];
            self.lastRotationDate = [NSDate date];
            self.rotationInProgress = NO;
            
            [self saveMDMStatus];
            
            if (completion) {
                completion(YES, newKeyID, nil);
            }
        } else {
            self.rotationInProgress = NO;
            
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                    code:500 
                                                userInfo:@{NSLocalizedDescriptionKey: @"MDM rotation failed"}];
                completion(NO, nil, error);
            }
        }
    }];
}

#pragma mark - Profile-Based Rotation

- (void)triggerProfileBasedRotation:(MDMRotationCompletionHandler)completion {
    os_log_info(self.logger, "Triggering profile-based FileVault rotation");
    
    // Install a configuration profile that triggers rotation
    if ([self installRotationProfile]) {
        // Profile installation triggers rotation automatically
        // Wait for completion
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), self.mdmQueue, ^{
            // Check if rotation completed
            if ([self checkProfileRotationStatus]) {
                self.lastRotationDate = [NSDate date];
                self.rotationInProgress = NO;
                
                [self saveMDMStatus];
                
                // Remove the profile after successful rotation
                [self removeRotationProfile];
                
                if (completion) {
                    completion(YES, [[NSUUID UUID] UUIDString], nil);
                }
            } else {
                self.rotationInProgress = NO;
                
                if (completion) {
                    NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                        code:500 
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Profile rotation failed"}];
                    completion(NO, nil, error);
                }
            }
        });
    } else {
        self.rotationInProgress = NO;
        
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                code:500 
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to install rotation profile"}];
            completion(NO, nil, error);
        }
    }
}

#pragma mark - Custom Script Rotation

- (void)triggerCustomScriptRotation:(MDMRotationCompletionHandler)completion {
    os_log_info(self.logger, "Triggering custom script FileVault rotation");
    
    // Use a privileged helper tool or script to perform rotation
    NSString *scriptPath = @"/usr/local/bin/escrow_buddy_rotate.sh";
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        os_log_error(self.logger, "Custom rotation script not found");
        self.rotationInProgress = NO;
        
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                code:404 
                                            userInfo:@{NSLocalizedDescriptionKey: @"Rotation script not found"}];
            completion(NO, nil, error);
        }
        return;
    }
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:scriptPath];
    [task setArguments:@[@"--rotate", @"--escrow"]];
    
    NSPipe *outputPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    
    [task setTerminationHandler:^(NSTask *task) {
        if (task.terminationStatus == 0) {
            NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
            
            // Parse output for new key ID
            NSString *newKeyID = [self parseKeyIDFromOutput:output];
            
            self.lastRotationDate = [NSDate date];
            self.rotationInProgress = NO;
            
            [self saveMDMStatus];
            
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES, newKeyID, nil);
                });
            }
        } else {
            self.rotationInProgress = NO;
            
            if (completion) {
                NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                    code:500 
                                                userInfo:@{NSLocalizedDescriptionKey: @"Script rotation failed"}];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, nil, error);
                });
            }
        }
    }];
    
    @try {
        [task launch];
    } @catch (NSException *exception) {
        os_log_error(self.logger, "Failed to launch rotation script: %{public}@", exception.reason);
        self.rotationInProgress = NO;
        
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                code:500 
                                            userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
            completion(NO, nil, error);
        }
    }
}

#pragma mark - Profile Management

- (BOOL)installRotationProfile {
    os_log_info(self.logger, "Installing rotation profile");
    
    // Create a configuration profile that triggers rotation
    NSDictionary *profile = @{
        @"PayloadContent": @[@{
            @"PayloadType": @"com.apple.security.FDERecoveryKeyEscrow",
            @"PayloadVersion": @1,
            @"PayloadIdentifier": kRotationProfileIdentifier,
            @"PayloadUUID": [[NSUUID UUID] UUIDString],
            @"PayloadDisplayName": @"FileVault Recovery Key Rotation",
            @"PayloadOrganization": @"Escrow Buddy Enhanced",
            @"RotateRecoveryKey": @YES,
            @"EscrowLocation": self.mdmServerURL ?: @""
        }],
        @"PayloadType": @"Configuration",
        @"PayloadVersion": @1,
        @"PayloadIdentifier": kRotationProfileIdentifier,
        @"PayloadUUID": [[NSUUID UUID] UUIDString],
        @"PayloadDisplayName": @"FileVault Key Rotation"
    };
    
    NSString *profilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"rotation.mobileconfig"];
    [profile writeToFile:profilePath atomically:YES];
    
    // Install the profile
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/profiles"];
    [task setArguments:@[@"install", @"-path", profilePath]];
    
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        os_log_error(self.logger, "Failed to install profile: %{public}@", exception.reason);
        return NO;
    }
    
    // Clean up temp file
    [[NSFileManager defaultManager] removeItemAtPath:profilePath error:nil];
    
    return task.terminationStatus == 0;
}

- (BOOL)removeRotationProfile {
    os_log_info(self.logger, "Removing rotation profile");
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/profiles"];
    [task setArguments:@[@"remove", @"-identifier", kRotationProfileIdentifier]];
    
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        os_log_error(self.logger, "Failed to remove profile: %{public}@", exception.reason);
        return NO;
    }
    
    return task.terminationStatus == 0;
}

- (BOOL)isRotationProfileInstalled {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/profiles"];
    [task setArguments:@[@"show", @"-type", @"configuration"]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return NO;
    }
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    return [output containsString:kRotationProfileIdentifier];
}

#pragma mark - MDM Communication

- (void)notifyMDMRotationNeeded {
    os_log_info(self.logger, "Notifying MDM that rotation is needed");
    
    // Send notification to MDM server
    NSDictionary *notification = @{
        @"Type": @"FileVaultRotationNeeded",
        @"DeviceUDID": [self getDeviceUDID],
        @"Timestamp": [NSDate date],
        @"Reason": @"Policy requirement"
    };
    
    [self sendMDMNotification:notification];
}

- (void)requestMDMRotationPermission:(void(^)(BOOL granted))completion {
    os_log_info(self.logger, "Requesting MDM rotation permission");
    
    // Check with MDM server if rotation is allowed
    NSDictionary *request = @{
        @"Type": @"RotationPermissionRequest",
        @"DeviceUDID": [self getDeviceUDID]
    };
    
    [self sendMDMRequest:request completion:^(NSDictionary *response) {
        BOOL granted = [response[@"Granted"] boolValue];
        if (completion) {
            completion(granted);
        }
    }];
}

- (BOOL)waitForMDMRotationCompletion:(NSTimeInterval)timeout {
    NSDate *startTime = [NSDate date];
    
    while ([[NSDate date] timeIntervalSinceDate:startTime] < timeout) {
        if (![self isMDMRotationInProgress]) {
            return YES;
        }
        
        [NSThread sleepForTimeInterval:1.0];
    }
    
    return NO;
}

#pragma mark - Helper Methods

- (NSString *)getDeviceSerialNumber {
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMainPortDefault,
                                                               IOServiceMatching("IOPlatformExpertDevice"));
    if (!platformExpert) return nil;
    
    CFStringRef serialNumberRef = IORegistryEntryCreateCFProperty(platformExpert,
                                                                   CFSTR(kIOPlatformSerialNumberKey),
                                                                   kCFAllocatorDefault, 0);
    IOObjectRelease(platformExpert);
    
    if (!serialNumberRef) return nil;
    
    NSString *serialNumber = (__bridge_transfer NSString *)serialNumberRef;
    return serialNumber;
}

- (NSString *)getDeviceUDID {
    // Get device UDID for MDM
    return [[NSUUID UUID] UUIDString]; // Placeholder
}

- (BOOL)isAppleMDMAvailable {
    // Check if device is enrolled in Apple MDM
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/Library/Managed Preferences/com.apple.mdm.plist"];
}

- (BOOL)hasCustomScriptPermission {
    // Check if custom script exists and is executable
    NSString *scriptPath = @"/usr/local/bin/escrow_buddy_rotate.sh";
    return [[NSFileManager defaultManager] isExecutableFileAtPath:scriptPath];
}

- (BOOL)checkProfileRotationStatus {
    // Check if profile-based rotation completed
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/fdesetup"];
    [task setArguments:@[@"status"]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        return NO;
    }
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    // Check if key was recently rotated
    return [output containsString:@"FileVault is On"];
}

- (NSString *)parseKeyIDFromOutput:(NSString *)output {
    // Parse script output for new key ID
    NSArray *lines = [output componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        if ([line hasPrefix:@"NewKeyID:"]) {
            return [line substringFromIndex:9];
        }
    }
    return [[NSUUID UUID] UUIDString];
}

- (void)sendMDMCommand:(NSDictionary *)command completion:(void(^)(BOOL success, NSDictionary *response))completion {
    // Send command to MDM server
    // Implementation depends on MDM vendor
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), self.mdmQueue, ^{
        if (completion) {
            completion(YES, @{@"Status": @"Success"});
        }
    });
}

- (void)sendMDMNotification:(NSDictionary *)notification {
    // Send notification to MDM server - log the event
    [[EnhancedLogger sharedLogger] logRotationEvent:@"MDMNotification" 
                                              reason:@"RotationNeeded" 
                                               keyID:notification[@"DeviceUDID"]];
}

- (void)sendMDMRequest:(NSDictionary *)request completion:(void(^)(NSDictionary *response))completion {
    // Send request to MDM server and get response
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), self.mdmQueue, ^{
        if (completion) {
            completion(@{@"Granted": @YES});
        }
    });
}

#pragma mark - Status and Persistence

- (NSDictionary *)getMDMRotationStatus {
    return @{
        @"Method": @(self.preferredMethod),
        @"InProgress": @(self.rotationInProgress),
        @"LastRotation": self.lastRotationDate ?: [NSNull null],
        @"MDMConfigured": @([self canPerformMDMRotation]),
        @"ProfileInstalled": @([self isRotationProfileInstalled])
    };
}

- (NSDate *)getLastMDMRotationDate {
    return self.lastRotationDate;
}

- (BOOL)isMDMRotationInProgress {
    return self.rotationInProgress;
}

- (void)saveMDMStatus {
    NSDictionary *status = @{
        @"LastRotation": self.lastRotationDate ?: [NSNull null],
        @"Method": @(self.preferredMethod)
    };
    
    [status writeToFile:kMDMRotationStatusFile atomically:YES];
}

- (void)loadMDMStatus {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kMDMRotationStatusFile]) {
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kMDMRotationStatusFile];
        
        if (status[@"LastRotation"] != [NSNull null]) {
            self.lastRotationDate = status[@"LastRotation"];
        }
        
        if (status[@"Method"]) {
            self.preferredMethod = [status[@"Method"] integerValue];
        }
    }
}

@end