//
//  MDMRotationHandler.m
//  Escrow Buddy Enhanced
//
//  Simplified version using Jamf binary for rotation - no API needed!
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
#import "ConfigurationManager.h"
#import <os/log.h>

static NSString *const kMDMRotationStatusFile = @"/var/db/escrow_buddy_mdm_status.plist";
static NSString *const kJamfBinaryPath = @"/usr/local/bin/jamf";
static NSString *const kRotationPolicyEvent = @"rotateFileVaultKey";

@interface MDMRotationHandler ()
@property (nonatomic, strong) os_log_t logger;
@property (nonatomic, strong) NSDate *lastRotationDate;
@property (nonatomic, assign) BOOL rotationInProgress;
@property (nonatomic, strong) dispatch_queue_t mdmQueue;
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
        _logger = os_log_create("com.macjediwizard.Escrow-Buddy-Enhanced", "MDMRotation");
        _mdmQueue = dispatch_queue_create("com.macjediwizard.escrow-buddy.mdm", DISPATCH_QUEUE_SERIAL);
        _mdmType = MDMTypeJamfPro;  // Default to Jamf
        _useMDMEscrow = YES;
        
        [self loadMDMStatus];
    }
    return self;
}

#pragma mark - MDM Rotation Methods

- (BOOL)canPerformMDMRotation {
    // Check if Jamf binary exists
    BOOL jamfExists = [[NSFileManager defaultManager] fileExistsAtPath:kJamfBinaryPath];
    
    if (!jamfExists) {
        os_log_error(self.logger, "Jamf binary not found at %{public}@", kJamfBinaryPath);
        return NO;
    }
    
    // Check if we're enrolled in Jamf
    NSTask *checkTask = [[NSTask alloc] init];
    checkTask.launchPath = kJamfBinaryPath;
    checkTask.arguments = @[@"checkJSSConnection"];
    
    NSPipe *outputPipe = [NSPipe pipe];
    checkTask.standardOutput = outputPipe;
    checkTask.standardError = outputPipe;
    
    @try {
        [checkTask launch];
        [checkTask waitUntilExit];
        
        BOOL enrolled = (checkTask.terminationStatus == 0);
        os_log_info(self.logger, "Jamf enrollment status: %{public}@", enrolled ? @"Enrolled" : @"Not enrolled");
        return enrolled;
    }
    @catch (NSException *exception) {
        os_log_error(self.logger, "Failed to check Jamf connection: %{public}@", exception.reason);
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
    
    if (![self canPerformMDMRotation]) {
        os_log_error(self.logger, "Cannot perform MDM rotation - Jamf not available");
        if (completion) {
            NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                code:503 
                                            userInfo:@{NSLocalizedDescriptionKey: @"Jamf not available"}];
            completion(NO, nil, error);
        }
        return;
    }
    
    self.rotationInProgress = YES;
    
    dispatch_async(self.mdmQueue, ^{
        [self executeJamfRotationWithCompletion:completion];
    });
}

- (void)executeJamfRotationWithCompletion:(MDMRotationCompletionHandler)completion {
    os_log_info(self.logger, "Executing FileVault rotation using Jamf binary");
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = kJamfBinaryPath;
    
    // Get rotation method from configuration
    NSString *method = [[NSUserDefaults standardUserDefaults] stringForKey:@"JamfRotationMethod"] ?: @"policy";
    
    if ([method isEqualToString:@"policy"]) {
        // Method 1: Use custom policy trigger (recommended)
        task.arguments = @[@"policy", @"-event", kRotationPolicyEvent];
        os_log_info(self.logger, "Using Jamf policy method with event: %{public}@", kRotationPolicyEvent);
    } else if ([method isEqualToString:@"recon"]) {
        // Method 2: Run recon to trigger smart group policy
        task.arguments = @[@"recon"];
        os_log_info(self.logger, "Using Jamf recon method");
    } else {
        // Default to policy method
        task.arguments = @[@"policy", @"-event", kRotationPolicyEvent];
    }
    
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;
    
    __weak typeof(self) weakSelf = self;
    
    [task setTerminationHandler:^(NSTask *terminatedTask) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        
        NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
        NSString *errorOutput = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        
        dispatch_async(strongSelf.mdmQueue, ^{
            if (terminatedTask.terminationStatus == 0) {
                os_log_info(strongSelf.logger, "Jamf command executed successfully");
                
                // Check if output indicates success
                BOOL success = YES;
                if ([output containsString:@"failed"] || [output containsString:@"error"]) {
                    success = NO;
                    os_log_error(strongSelf.logger, "Jamf output indicates failure: %{public}@", output);
                }
                
                if (success) {
                    NSString *newKeyID = [[NSUUID UUID] UUIDString];
                    strongSelf.lastRotationDate = [NSDate date];
                    strongSelf.rotationInProgress = NO;
                    
                    [strongSelf saveMDMStatus];
                    [strongSelf recordRotationEvent:@"JamfBinary" success:YES];
                    
                    os_log_info(strongSelf.logger, "FileVault key rotation completed successfully via Jamf");
                    
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(YES, newKeyID, nil);
                        });
                    }
                } else {
                    strongSelf.rotationInProgress = NO;
                    [strongSelf recordRotationEvent:@"JamfBinary" success:NO];
                    
                    NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                        code:500 
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Jamf policy indicated failure",
                                                             @"Output": output ?: @""}];
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(NO, nil, error);
                        });
                    }
                }
            } else {
                strongSelf.rotationInProgress = NO;
                [strongSelf recordRotationEvent:@"JamfBinary" success:NO];
                
                os_log_error(strongSelf.logger, "Jamf command failed with exit code %d", terminatedTask.terminationStatus);
                if (errorOutput.length > 0) {
                    os_log_error(strongSelf.logger, "Error output: %{public}@", errorOutput);
                }
                
                NSError *error = [NSError errorWithDomain:@"MDMRotation" 
                                                    code:terminatedTask.terminationStatus 
                                                userInfo:@{NSLocalizedDescriptionKey: @"Jamf command failed",
                                                         @"ErrorOutput": errorOutput ?: @"",
                                                         @"Output": output ?: @""}];
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(NO, nil, error);
                    });
                }
            }
        });
    }];
    
    NSError *launchError;
    if (![task launchAndReturnError:&launchError]) {
        os_log_error(self.logger, "Failed to launch Jamf binary: %{public}@", launchError.localizedDescription);
        self.rotationInProgress = NO;
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil, launchError);
            });
        }
    }
}

- (void)notifyMDMRotationNeeded {
    os_log_info(self.logger, "Notifying MDM that rotation is needed");
    
    // Write a flag that can be picked up by an Extension Attribute
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    status[@"RotationNeeded"] = @YES;
    status[@"RequestDate"] = [NSDate date];
    status[@"Reason"] = @"Policy-based rotation required";
    
    NSString *eaPath = @"/Library/Application Support/JAMF/escrow_buddy_status.plist";
    
    // Create directory if needed
    NSString *directory = [eaPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:nil];
    
    // Write status for Extension Attribute
    [status writeToFile:eaPath atomically:YES];
    
    // Optionally run recon to update EA immediately
    BOOL enableImmediateRecon = [[NSUserDefaults standardUserDefaults] boolForKey:@"EnableImmediateRecon"];
    if (enableImmediateRecon) {
        dispatch_async(self.mdmQueue, ^{
            NSTask *reconTask = [[NSTask alloc] init];
            reconTask.launchPath = kJamfBinaryPath;
            reconTask.arguments = @[@"recon"];
            
            @try {
                [reconTask launch];
                os_log_info(self.logger, "Triggered Jamf recon to update rotation status");
            }
            @catch (NSException *exception) {
                os_log_error(self.logger, "Failed to run recon: %{public}@", exception.reason);
            }
        });
    }
}

#pragma mark - Status Management

- (void)loadMDMStatus {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kMDMRotationStatusFile]) {
        NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:kMDMRotationStatusFile];
        self.lastRotationDate = status[@"LastRotationDate"];
        self.rotationInProgress = [status[@"RotationInProgress"] boolValue];
        
        os_log_info(self.logger, "Loaded MDM status - Last rotation: %{public}@", 
                   self.lastRotationDate ?: @"Never");
    }
}

- (void)saveMDMStatus {
    NSMutableDictionary *status = [NSMutableDictionary dictionary];
    
    if (self.lastRotationDate) {
        status[@"LastRotationDate"] = self.lastRotationDate;
    }
    status[@"RotationInProgress"] = @(self.rotationInProgress);
    status[@"MDMType"] = @"JamfBinary";
    
    [status writeToFile:kMDMRotationStatusFile atomically:YES];
}

- (void)recordRotationEvent:(NSString *)method success:(BOOL)success {
    NSMutableDictionary *event = [NSMutableDictionary dictionary];
    event[@"Date"] = [NSDate date];
    event[@"Method"] = method;
    event[@"Success"] = @(success);
    
    // Load existing history
    NSString *historyPath = @"/Library/Preferences/com.macjediwizard.Escrow-Buddy-Enhanced.plist";
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:historyPath] ?: [NSMutableDictionary dictionary];
    NSMutableArray *history = [prefs[@"RotationHistory"] mutableCopy] ?: [NSMutableArray array];
    
    [history addObject:event];
    
    // Keep only last 100 events
    if (history.count > 100) {
        [history removeObjectsInRange:NSMakeRange(0, history.count - 100)];
    }
    
    prefs[@"RotationHistory"] = history;
    prefs[@"LastRotation"] = [NSDate date];
    prefs[@"RotationCount"] = @([prefs[@"RotationCount"] integerValue] + 1);
    
    [prefs writeToFile:historyPath atomically:YES];
}

- (NSDate *)lastSuccessfulRotation {
    return self.lastRotationDate;
}

- (BOOL)isRotationInProgress {
    return self.rotationInProgress;
}

@end