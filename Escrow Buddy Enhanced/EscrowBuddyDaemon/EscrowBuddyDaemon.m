//
//  EscrowBuddyDaemon.m
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

#import "EscrowBuddyDaemon.h"
#import "EscrowBuddyXPCProtocol.h"
#import "RotationManager.h"
#import "ConfigurationManager.h"
#import "KeyLifecycleTracker.h"
#import "EnhancedLogger.h"
#import "ComplianceReporter.h"
#import "MDMRotationHandler.h"
#import "RecoveryKeyUsageDetector.h"
#import <os/log.h>

static NSString *const kDaemonIdentifier = @"com.netflix.escrow-buddy.daemon";
static NSString *const kXPCServiceName = @"com.netflix.escrow-buddy.xpc";
static NSString *const kDaemonStatusFile = @"/var/db/escrow_buddy_daemon_status.plist";

@interface EscrowBuddyDaemon () <NSXPCListenerDelegate>
@property (nonatomic, strong) NSTimer *rotationCheckTimer;
@property (nonatomic, strong) NSXPCListener *xpcListener;
@property (nonatomic, strong) NSMutableArray *xpcConnections;
@property (nonatomic, strong) dispatch_queue_t daemonQueue;
@property (nonatomic, assign) DaemonStatus status;
@property (nonatomic, strong) NSDate *lastRotationDate;
@property (nonatomic, strong) NSDate *nextScheduledCheck;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, strong) os_log_t logger;
@property (nonatomic, strong) RotationManager *rotationManager;
@property (nonatomic, strong) ConfigurationManager *configManager;
@property (nonatomic, strong) KeyLifecycleTracker *lifecycleTracker;
@property (nonatomic, strong) EnhancedLogger *enhancedLogger;
@property (nonatomic, strong) MDMRotationHandler *mdmHandler;
@property (nonatomic, strong) RecoveryKeyUsageDetector *recoveryKeyDetector;
@end

@implementation EscrowBuddyDaemon

#pragma mark - Singleton

+ (instancetype)sharedDaemon {
    static EscrowBuddyDaemon *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logger = os_log_create("com.netflix.Escrow-Buddy", "Daemon");
        _daemonQueue = dispatch_queue_create("com.netflix.escrow-buddy.daemon", DISPATCH_QUEUE_SERIAL);
        _xpcConnections = [NSMutableArray array];
        _status = DaemonStatusIdle;
        
        _rotationManager = [RotationManager sharedManager];
        _configManager = [ConfigurationManager sharedManager];
        _lifecycleTracker = [KeyLifecycleTracker sharedTracker];
        _enhancedLogger = [EnhancedLogger sharedLogger];
        _mdmHandler = [MDMRotationHandler sharedHandler];
        
        // Initialize recovery key usage detector
        _recoveryKeyDetector = [[RecoveryKeyUsageDetector alloc] initWithRotationManager:_rotationManager
                                                                       lifecycleTracker:_lifecycleTracker];
        
        [self loadDaemonState];
    }
    return self;
}

#pragma mark - Daemon Lifecycle

- (void)startDaemon {
    os_log_info(self.logger, "Starting Escrow Buddy Daemon");
    
    if (self.isRunning) {
        os_log_info(self.logger, "Daemon is already running");
        return;
    }
    
    self.isRunning = YES;
    self.status = DaemonStatusIdle;
    
    // Start XPC service for IPC
    [self startXPCService];
    
    // Load configuration
    [self.configManager reloadConfiguration];
    
    // Schedule first rotation check
    [self scheduleNextRotationCheck];
    
    // Start recovery key usage monitoring if enabled
    if ([[self.configManager getValueForKey:@"MonitorRecoveryKeyUsage" defaultValue:@YES] boolValue]) {
        [self.recoveryKeyDetector startMonitoring];
        os_log_info(self.logger, "Started recovery key usage monitoring");
    }
    
    // Perform initial health check
    [self performHealthCheck];
    
    // Save daemon state
    [self saveDaemonState];
    
    os_log_info(self.logger, "Daemon started successfully");
    
    // Notify delegate
    if ([self.delegate respondsToSelector:@selector(daemonStatusChanged:)]) {
        [self.delegate daemonStatusChanged:self.status];
    }
}

- (void)stopDaemon {
    os_log_info(self.logger, "Stopping Escrow Buddy Daemon");
    
    self.isRunning = NO;
    self.status = DaemonStatusIdle;
    
    // Cancel scheduled rotation
    [self cancelScheduledRotation];
    
    // Stop recovery key monitoring
    [self.recoveryKeyDetector stopMonitoring];
    
    // Stop XPC service
    [self stopXPCService];
    
    // Save final state
    [self saveDaemonState];
    
    os_log_info(self.logger, "Daemon stopped");
}

- (void)restartDaemon {
    os_log_info(self.logger, "Restarting daemon");
    [self stopDaemon];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self startDaemon];
    });
}

- (BOOL)isDaemonRunning {
    return self.isRunning;
}

#pragma mark - Rotation Operations

- (BOOL)performBackgroundRotation {
    os_log_info(self.logger, "Starting background FileVault key rotation");
    
    if (self.status == DaemonStatusRotating) {
        os_log_error(self.logger, "Rotation already in progress");
        return NO;
    }
    
    if (![self canPerformRotation]) {
        os_log_error(self.logger, "Cannot perform rotation at this time");
        return NO;
    }
    
    self.status = DaemonStatusRotating;
    
    if ([self.delegate respondsToSelector:@selector(daemonDidStartRotation)]) {
        [self.delegate daemonDidStartRotation];
    }
    
    // Generate new recovery key using fdesetup
    BOOL success = [self rotateFileVaultKey];
    
    if (success) {
        os_log_info(self.logger, "Background rotation completed successfully");
        
        self.lastRotationDate = [NSDate date];
        
        // Record rotation in lifecycle tracker
        NSString *newKeyID = [[NSUUID UUID] UUIDString];
        [self.lifecycleTracker rotateKey:newKeyID reason:@"Automatic background rotation"];
        
        // Clear any manual rotation flags
        [self.rotationManager clearManualRotationFlag];
        
        // Generate compliance report if needed
        if (self.configManager.enableComplianceReporting) {
            [[ComplianceReporter sharedReporter] generateAndSubmitScheduledReport];
        }
    } else {
        os_log_error(self.logger, "Background rotation failed");
    }
    
    self.status = DaemonStatusIdle;
    
    if ([self.delegate respondsToSelector:@selector(daemonDidCompleteRotation:error:)]) {
        NSError *error = success ? nil : [NSError errorWithDomain:@"EscrowBuddyDaemon" 
                                                             code:500 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Rotation failed"}];
        [self.delegate daemonDidCompleteRotation:success error:error];
    }
    
    // Schedule next check
    [self scheduleNextRotationCheck];
    
    return success;
}

- (void)performBackgroundRotationWithCompletion:(DaemonCompletionHandler)completion {
    dispatch_async(self.daemonQueue, ^{
        BOOL success = [self performBackgroundRotation];
        if (completion) {
            NSError *error = success ? nil : [NSError errorWithDomain:@"EscrowBuddyDaemon" 
                                                                 code:500 
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Rotation failed"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(success, error);
            });
        }
    });
}

- (BOOL)isRotationNeeded {
    // Use the rotation manager's logic
    return [self.rotationManager shouldRotateKey];
}

- (BOOL)canPerformRotation {
    // Check if we can perform rotation
    // 1. FileVault must be enabled
    // 2. MDM escrow profile must be configured
    // 3. Not currently rotating
    // 4. System is not in power nap or sleep
    
    if (self.status == DaemonStatusRotating) {
        return NO;
    }
    
    // Check FileVault status
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/fdesetup"];
    [task setArguments:@[@"status"]];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];
    
    [task launch];
    [task waitUntilExit];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    if (![output containsString:@"FileVault is On"]) {
        os_log_error(self.logger, "FileVault is not enabled");
        return NO;
    }
    
    return YES;
}

#pragma mark - Scheduling

- (void)scheduleNextRotationCheck {
    [self cancelScheduledRotation];
    
    NSInteger intervalDays = self.configManager.rotationIntervalDays;
    NSTimeInterval interval = intervalDays * 24 * 60 * 60; // Convert days to seconds
    
    // For testing, allow shorter intervals
    #ifdef DEBUG
    if (intervalDays < 1) {
        interval = 60 * 60; // 1 hour minimum in debug
    }
    #endif
    
    self.nextScheduledCheck = [NSDate dateWithTimeIntervalSinceNow:interval];
    
    os_log_info(self.logger, "Scheduling next rotation check for %{public}@", self.nextScheduledCheck);
    
    self.rotationCheckTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                              target:self
                                                            selector:@selector(rotationCheckTimerFired:)
                                                            userInfo:nil
                                                             repeats:NO];
    
    [self saveDaemonState];
}

- (void)scheduleRotationCheckAtDate:(NSDate *)date {
    [self cancelScheduledRotation];
    
    NSTimeInterval interval = [date timeIntervalSinceNow];
    if (interval < 0) {
        // Date is in the past, schedule immediately
        interval = 0;
    }
    
    self.nextScheduledCheck = date;
    
    self.rotationCheckTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                              target:self
                                                            selector:@selector(rotationCheckTimerFired:)
                                                            userInfo:nil
                                                             repeats:NO];
    
    [self saveDaemonState];
}

- (void)cancelScheduledRotation {
    if (self.rotationCheckTimer) {
        [self.rotationCheckTimer invalidate];
        self.rotationCheckTimer = nil;
        self.nextScheduledCheck = nil;
    }
}

- (NSTimeInterval)timeUntilNextCheck {
    if (!self.nextScheduledCheck) {
        return -1;
    }
    
    return [self.nextScheduledCheck timeIntervalSinceNow];
}

- (void)rotationCheckTimerFired:(NSTimer *)timer {
    os_log_info(self.logger, "Rotation check timer fired");
    
    self.status = DaemonStatusChecking;
    
    if ([self isRotationNeeded]) {
        os_log_info(self.logger, "Rotation is needed, starting background rotation");
        [self performBackgroundRotationWithCompletion:nil];
    } else {
        os_log_info(self.logger, "No rotation needed at this time");
        self.status = DaemonStatusIdle;
        [self scheduleNextRotationCheck];
    }
}

#pragma mark - XPC Communication

- (void)startXPCService {
    self.xpcListener = [[NSXPCListener alloc] initWithMachServiceName:kXPCServiceName];
    self.xpcListener.delegate = self;
    [self.xpcListener resume];
    
    os_log_info(self.logger, "XPC service started: %{public}@", kXPCServiceName);
}

- (void)stopXPCService {
    [self.xpcListener invalidate];
    self.xpcListener = nil;
    
    for (NSXPCConnection *connection in self.xpcConnections) {
        [connection invalidate];
    }
    [self.xpcConnections removeAllObjects];
    
    os_log_info(self.logger, "XPC service stopped");
}

- (void)handleXPCMessage:(NSDictionary *)message reply:(void(^)(NSDictionary *))reply {
    NSString *command = message[@"command"];
    
    os_log_info(self.logger, "Received XPC message: %{public}@", command);
    
    if ([command isEqualToString:@"getStatus"]) {
        reply([self getDaemonStatus]);
    } else if ([command isEqualToString:@"rotateNow"]) {
        [self performBackgroundRotationWithCompletion:^(BOOL success, NSError *error) {
            reply(@{@"success": @(success), @"error": error ? error.localizedDescription : NSNull.null});
        }];
    } else if ([command isEqualToString:@"checkRotation"]) {
        reply(@{@"rotationNeeded": @([self isRotationNeeded])});
    } else if ([command isEqualToString:@"reloadConfig"]) {
        [self reloadConfiguration];
        reply(@{@"success": @YES});
    } else {
        reply(@{@"error": @"Unknown command"});
    }
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // Configure the connection
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(EscrowBuddyDaemonProtocol)];
    newConnection.exportedObject = self;
    
    // Store the connection
    [self.xpcConnections addObject:newConnection];
    
    newConnection.invalidationHandler = ^{
        [self.xpcConnections removeObject:newConnection];
    };
    
    [newConnection resume];
    
    return YES;
}

#pragma mark - Configuration

- (void)reloadConfiguration {
    os_log_info(self.logger, "Reloading configuration");
    
    [self.configManager reloadConfiguration];
    
    // Reschedule rotation check if interval changed
    [self scheduleNextRotationCheck];
}

- (NSDictionary *)getCurrentConfiguration {
    return [self.configManager getCurrentConfiguration];
}

- (BOOL)updateConfiguration:(NSDictionary *)config {
    return [self.configManager updateConfiguration:config];
}

#pragma mark - Status and Monitoring

- (NSDictionary *)getDaemonStatus {
    return @{
        @"isRunning": @(self.isRunning),
        @"status": @(self.status),
        @"lastRotation": self.lastRotationDate ?: [NSNull null],
        @"nextCheck": self.nextScheduledCheck ?: [NSNull null],
        @"keyAge": @([self getCurrentKeyAgeDays]),
        @"rotationNeeded": @([self isRotationNeeded]),
        @"configuration": [self getCurrentConfiguration]
    };
}

- (NSArray *)getRotationHistory:(NSInteger)count {
    return [[self.lifecycleTracker getRotationHistory] subarrayWithRange:NSMakeRange(0, MIN(count, [self.lifecycleTracker getRotationHistory].count))];
}

- (NSDictionary *)getStatistics {
    return [self.lifecycleTracker getKeyStatistics];
}

#pragma mark - XPC Protocol Implementation (EscrowBuddyDaemonProtocol)

- (void)getDaemonStatusWithReply:(void (^)(NSDictionary *status))reply {
    if (reply) {
        reply([self getDaemonStatus]);
    }
}

- (void)getKeyInfoWithReply:(void (^)(NSDictionary *keyInfo))reply {
    if (reply) {
        NSDictionary *keyInfo = @{
            @"currentKeyAge": @([self getCurrentKeyAgeDays]),
            @"lastRotation": self.lastRotationDate ?: [NSNull null],
            @"rotationNeeded": @([self isRotationNeeded]),
            @"keyID": [self.lifecycleTracker getCurrentKeyID] ?: @"unknown"
        };
        reply(keyInfo);
    }
}

- (void)getRotationHistoryWithCount:(NSInteger)count reply:(void (^)(NSArray *history))reply {
    if (reply) {
        reply([self getRotationHistory:count]);
    }
}

- (void)checkRotationNeededWithReply:(void (^)(BOOL needed, NSString * _Nullable reason))reply {
    if (reply) {
        BOOL needed = [self isRotationNeeded];
        NSString *reason = nil;
        if (needed) {
            RotationReason rotationReason = [self.rotationManager getRotationReason];
            switch (rotationReason) {
                case RotationReasonAge:
                    reason = @"Key age exceeds maximum";
                    break;
                case RotationReasonUsed:
                    reason = @"Recovery key was used";
                    break;
                case RotationReasonCompliance:
                    reason = @"Compliance requirement";
                    break;
                case RotationReasonManual:
                    reason = @"Manual rotation requested";
                    break;
                case RotationReasonScheduled:
                    reason = @"Scheduled rotation";
                    break;
                default:
                    reason = @"Unknown reason";
                    break;
            }
        }
        reply(needed, reason);
    }
}

- (void)performRotationWithReason:(NSString *)reason reply:(void (^)(BOOL success, NSError * _Nullable error))reply {
    [self performBackgroundRotationWithCompletion:^(BOOL success, NSError *error) {
        if (reply) {
            reply(success, error);
        }
    }];
}

- (void)forceRotationWithReply:(void (^)(BOOL started))reply {
    dispatch_async(self.daemonQueue, ^{
        BOOL started = NO;
        if (self.status != DaemonStatusRotating) {
            [self performBackgroundRotationWithCompletion:nil];
            started = YES;
        }
        if (reply) {
            dispatch_async(dispatch_get_main_queue(), ^{
                reply(started);
            });
        }
    });
}

- (void)getComplianceStatusWithReply:(void (^)(NSDictionary *status))reply {
    if (reply) {
        ComplianceReporter *reporter = [ComplianceReporter sharedReporter];
        ComplianceStatus status = [reporter checkCompliance];
        NSDictionary *complianceInfo = @{
            @"compliant": @(status == ComplianceStatusCompliant),
            @"status": @(status),
            @"violations": [reporter getComplianceViolations],
            @"recommendations": [reporter getComplianceRecommendations]
        };
        reply(complianceInfo);
    }
}

- (void)generateComplianceReportWithFormat:(NSString *)format reply:(void (^)(NSData * _Nullable reportData, NSError * _Nullable error))reply {
    if (reply) {
        ComplianceReporter *reporter = [ComplianceReporter sharedReporter];
        ReportFormat reportFormat = ReportFormatJSON;
        if ([format isEqualToString:@"XML"]) {
            reportFormat = ReportFormatXML;
        } else if ([format isEqualToString:@"CSV"]) {
            reportFormat = ReportFormatCSV;
        } else if ([format isEqualToString:@"HTML"]) {
            reportFormat = ReportFormatHTML;
        }
        
        NSData *reportData = [reporter generateReportData:reportFormat];
        reply(reportData, nil);
    }
}

- (void)updateConfigurationValue:(NSString *)key value:(id)value reply:(void (^)(BOOL success))reply {
    BOOL success = [self.configManager updateConfigurationValue:key value:value];
    if (reply) {
        reply(success);
    }
}

- (void)reloadConfigurationWithReply:(void (^)(void))reply {
    [self reloadConfiguration];
    if (reply) {
        reply();
    }
}

- (void)enableDebugModeWithReply:(void (^)(void))reply {
    [self enableDebugMode:YES];
    if (reply) {
        reply();
    }
}

- (void)performHealthCheckWithReply:(void (^)(NSDictionary *health))reply {
    [self performHealthCheck];
    if (reply) {
        NSDictionary *health = @{
            @"canRotate": @([self canPerformRotation]),
            @"configValid": @([self.configManager validateConfiguration]),
            @"keyAge": @([self getCurrentKeyAgeDays]),
            @"daemonStatus": @(self.status)
        };
        reply(health);
    }
}

- (void)notifyLoginOccurredForUser:(NSString *)username reply:(void (^)(void))reply {
    os_log_info(self.logger, "Login notification received for user: %{public}@", username);
    
    // Record login event
    [self.enhancedLogger log:EscrowBuddyLogLevelInfo 
                      message:[NSString stringWithFormat:@"User login: %@", username]
                     category:@"UserActivity"];
    
    // Check if rotation is needed after login
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), self.daemonQueue, ^{
        if ([self isRotationNeeded]) {
            os_log_info(self.logger, "Rotation needed after login, scheduling background rotation");
            [self scheduleNextRotationCheck];
        }
    });
    
    if (reply) {
        reply();
    }
}

- (void)notifyLogoutOccurredForUser:(NSString *)username reply:(void (^)(void))reply {
    os_log_info(self.logger, "Logout notification received for user: %{public}@", username);
    
    // Record logout event
    [self.enhancedLogger log:EscrowBuddyLogLevelInfo 
                      message:[NSString stringWithFormat:@"User logout: %@", username]
                     category:@"UserActivity"];
    
    if (reply) {
        reply();
    }
}

- (void)notifyKeyRotatedByPlugin:(NSDictionary *)rotationInfo reply:(void (^)(void))reply {
    os_log_info(self.logger, "Plugin rotated key notification received");
    
    // Update our state to reflect the plugin's rotation
    NSString *keyID = rotationInfo[@"keyID"];
    NSString *user = rotationInfo[@"user"];
    NSDate *timestamp = rotationInfo[@"timestamp"];
    
    if (keyID) {
        // Record the rotation
        [self.lifecycleTracker rotateKey:keyID reason:@"Plugin rotation during login"];
        self.lastRotationDate = timestamp ?: [NSDate date];
        
        // Clear any pending rotation flags
        [self.rotationManager clearManualRotationFlag];
        
        // Log the event
        [self.enhancedLogger logRotationEvent:@"Plugin-initiated rotation" 
                                        reason:[NSString stringWithFormat:@"Login by user: %@", user]
                                         keyID:keyID];
    }
    
    // Reset rotation timer since we just rotated
    [self scheduleNextRotationCheck];
    
    if (reply) {
        reply();
    }
}

- (void)getConfigurationWithReply:(void (^)(NSDictionary *config))reply {
    if (reply) {
        reply([self getCurrentConfiguration]);
    }
}

- (void)updateConfiguration:(NSDictionary *)config reply:(void (^)(BOOL success, NSError * _Nullable error))reply {
    BOOL success = [self updateConfiguration:config];
    if (reply) {
        NSError *error = success ? nil : [NSError errorWithDomain:@"EscrowBuddyDaemon" 
                                                             code:400 
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to update configuration"}];
        reply(success, error);
    }
}

- (void)reloadConfigurationWithReply:(void (^)(BOOL success))reply {
    [self reloadConfiguration];
    if (reply) {
        reply(YES);
    }
}

- (void)getStatisticsWithReply:(void (^)(NSDictionary *stats))reply {
    if (reply) {
        reply([self getStatistics]);
    }
}

- (void)getDiagnosticsWithReply:(void (^)(NSDictionary *diagnostics))reply {
    if (reply) {
        NSDictionary *diagnostics = @{
            @"daemonVersion": @"2.0.0",
            @"uptime": @([self getUptime]),
            @"rotationCount": @([self.lifecycleTracker getTotalRotationCount]),
            @"lastRotation": self.lastRotationDate ?: [NSNull null],
            @"xpcConnections": @(self.xpcConnections.count),
            @"configSource": @([self.configManager getConfigurationSource])
        };
        reply(diagnostics);
    }
}

- (NSTimeInterval)getUptime {
    // This would need to track when daemon started
    return [[NSDate date] timeIntervalSince1970];
}

- (void)performHealthCheck {
    os_log_info(self.logger, "Performing health check");
    
    // Check FileVault status
    BOOL canRotate = [self canPerformRotation];
    
    // Check configuration
    BOOL configValid = [self.configManager validateConfiguration];
    
    // Check key lifecycle data
    NSInteger keyAge = [self getCurrentKeyAgeDays];
    
    // Log health status
    os_log_info(self.logger, "Health Check - Can Rotate: %d, Config Valid: %d, Key Age: %ld days", 
                canRotate, configValid, (long)keyAge);
    
    // Check if immediate rotation is needed
    if (keyAge > self.configManager.maxKeyAge) {
        os_log_error(self.logger, "Key age exceeds maximum, immediate rotation required");
        [self performBackgroundRotationWithCompletion:nil];
    }
}

#pragma mark - Key Operations

- (BOOL)rotateFileVaultKey {
    os_log_info(self.logger, "Executing FileVault key rotation via MDM");
    
    // Check if MDM rotation is available
    if (![self.mdmHandler canPerformMDMRotation]) {
        os_log_error(self.logger, "MDM rotation not available");
        
        // Notify MDM that rotation is needed but cannot be performed
        [self.mdmHandler notifyMDMRotationNeeded];
        
        return NO;
    }
    
    __block BOOL rotationSuccess = NO;
    __block NSString *newKeyID = nil;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    // Perform MDM-triggered rotation
    [self.mdmHandler performMDMRotationWithCompletion:^(BOOL success, NSString *keyID, NSError *error) {
        rotationSuccess = success;
        newKeyID = keyID;
        
        if (success) {
            os_log_info(self.logger, "MDM rotation completed successfully with key ID: %{public}@", keyID);
            
            // Log success
            [self.enhancedLogger logRotationEvent:@"BackgroundRotation" 
                                          reason:@"Scheduled" 
                                           keyID:keyID ?: [[NSUUID UUID] UUIDString]];
        } else {
            os_log_error(self.logger, "MDM rotation failed: %{public}@", error.localizedDescription);
        }
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    // Wait for rotation to complete (with timeout)
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC)); // 5 minute timeout
    long result = dispatch_semaphore_wait(semaphore, timeout);
    
    if (result != 0) {
        os_log_error(self.logger, "MDM rotation timed out");
        return NO;
    }
    
    return rotationSuccess;
}

- (BOOL)verifyCurrentKey {
    // Verify the current recovery key is valid
    // This would typically involve checking with MDM or using fdesetup
    return YES;
}

- (NSString *)getCurrentKeyIdentifier {
    KeyMetadata *currentKey = [self.lifecycleTracker getCurrentKey];
    return currentKey.keyID;
}

- (NSInteger)getCurrentKeyAgeDays {
    return [self.lifecycleTracker getCurrentKeyAgeDays];
}

#pragma mark - State Persistence

- (void)saveDaemonState {
    NSDictionary *state = @{
        @"lastRotation": self.lastRotationDate ?: [NSNull null],
        @"nextCheck": self.nextScheduledCheck ?: [NSNull null],
        @"status": @(self.status),
        @"isRunning": @(self.isRunning)
    };
    
    [state writeToFile:kDaemonStatusFile atomically:YES];
}

- (void)loadDaemonState {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kDaemonStatusFile]) {
        NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:kDaemonStatusFile];
        
        if (state[@"lastRotation"] != [NSNull null]) {
            self.lastRotationDate = state[@"lastRotation"];
        }
        
        if (state[@"nextCheck"] != [NSNull null]) {
            self.nextScheduledCheck = state[@"nextCheck"];
        }
    }
}

#pragma mark - Logging and Debugging

- (void)enableDebugMode:(BOOL)enable {
    // Enable/disable debug logging
    os_log_info(self.logger, "Debug mode %{public}@", enable ? @"enabled" : @"disabled");
}

- (NSArray *)getRecentLogs:(NSInteger)count {
    return [self.enhancedLogger getRecentLogs:count];
}

- (void)clearLogs {
    // Clear daemon-specific logs
    os_log_info(self.logger, "Clearing daemon logs");
}

@end