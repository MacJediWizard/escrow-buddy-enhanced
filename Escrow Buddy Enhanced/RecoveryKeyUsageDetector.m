/**
 * RecoveryKeyUsageDetector.m
 * Escrow Buddy Enhanced
 *
 * Implementation of FileVault recovery key usage detection
 */

#import "RecoveryKeyUsageDetector.h"
#import "RotationManager.h"
#import "KeyLifecycleTracker.h"
#import "EnhancedLogger.h"
#import <os/log.h>
#import <Security/Security.h>

// Notification names
NSString * const RecoveryKeyUsedNotification = @"RecoveryKeyUsedNotification";
NSString * const RecoveryKeyUsedDateKey = @"RecoveryKeyUsedDate";
NSString * const RecoveryKeyUsedMethodKey = @"RecoveryKeyUsedMethod";
NSString * const RecoveryKeyUsedUserKey = @"RecoveryKeyUsedUser";

// Log markers to detect recovery key usage
static NSString * const kAuthLogPath = @"/var/log/system.log";
static NSString * const kRecoveryKeyMarker = @"FileVault recovery";
static NSString * const kFDERecoveryMarker = @"FDERecoveryAgent";
static NSString * const kUnlockMarker = @"unlock.*recovery";

@interface RecoveryKeyUsageDetector ()

@property (nonatomic, strong) RotationManager *rotationManager;
@property (nonatomic, strong) KeyLifecycleTracker *lifecycleTracker;
@property (nonatomic, strong) EnhancedLogger *logger;
@property (nonatomic, strong) NSTimer *monitoringTimer;
@property (nonatomic, strong) dispatch_queue_t detectionQueue;
@property (nonatomic, strong) NSDate *lastCheckDate;
@property (nonatomic, assign) NSInteger detectionCount;
@property (nonatomic, assign) BOOL isMonitoring;
@property (nonatomic, strong) NSMutableDictionary *detectionCache;
@property (nonatomic, strong) os_log_t log;

@end

@implementation RecoveryKeyUsageDetector

#pragma mark - Initialization

+ (instancetype)sharedDetector {
    static RecoveryKeyUsageDetector *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[RecoveryKeyUsageDetector alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithRotationManager:(RotationManager *)rotationManager
                      lifecycleTracker:(KeyLifecycleTracker *)lifecycleTracker {
    self = [super init];
    if (self) {
        _rotationManager = rotationManager;
        _lifecycleTracker = lifecycleTracker;
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _logger = [[EnhancedLogger alloc] initWithSubsystem:@"com.netflix.Escrow-Buddy"
                                                category:@"RecoveryKeyDetector"];
    _log = os_log_create("com.netflix.Escrow-Buddy", "RecoveryKeyDetector");
    _detectionQueue = dispatch_queue_create("com.netflix.escrow-buddy.detection", DISPATCH_QUEUE_SERIAL);
    _detectionCache = [NSMutableDictionary dictionary];
    _detectionMethod = RecoveryKeyDetectionMethodAll;
    _autoMarkAsUsed = YES;
    _triggerRotation = NO;
    _checkInterval = 300; // 5 minutes default
    _detectionCount = 0;
    _isMonitoring = NO;
    
    [self loadConfiguration];
}

- (void)loadConfiguration {
    // Load configuration from preferences
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if ([defaults objectForKey:@"RecoveryKeyDetectionMethod"]) {
        self.detectionMethod = [defaults integerForKey:@"RecoveryKeyDetectionMethod"];
    }
    
    if ([defaults objectForKey:@"AutoMarkKeyAsUsed"]) {
        self.autoMarkAsUsed = [defaults boolForKey:@"AutoMarkKeyAsUsed"];
    }
    
    if ([defaults objectForKey:@"TriggerRotationOnRecoveryKeyUse"]) {
        self.triggerRotation = [defaults boolForKey:@"TriggerRotationOnRecoveryKeyUse"];
    }
    
    if ([defaults objectForKey:@"RecoveryKeyCheckInterval"]) {
        self.checkInterval = [defaults doubleForKey:@"RecoveryKeyCheckInterval"];
    }
    
    os_log_info(self.log, "Recovery key detector configured - Method: %ld, AutoMark: %d, TriggerRotation: %d",
                (long)self.detectionMethod, self.autoMarkAsUsed, self.triggerRotation);
}

#pragma mark - Monitoring Control

- (void)startMonitoring {
    if (self.isMonitoring) {
        os_log_info(self.log, "Recovery key monitoring already active");
        return;
    }
    
    os_log_info(self.log, "Starting recovery key usage monitoring");
    
    self.isMonitoring = YES;
    
    // Start periodic checking
    self.monitoringTimer = [NSTimer scheduledTimerWithTimeInterval:self.checkInterval
                                                            target:self
                                                          selector:@selector(performScheduledCheck)
                                                          userInfo:nil
                                                           repeats:YES];
    
    // Perform initial check
    [self performScheduledCheck];
    
    // Register for system notifications
    [self registerForSystemNotifications];
}

- (void)stopMonitoring {
    if (!self.isMonitoring) {
        return;
    }
    
    os_log_info(self.log, "Stopping recovery key usage monitoring");
    
    self.isMonitoring = NO;
    
    [self.monitoringTimer invalidate];
    self.monitoringTimer = nil;
    
    [self unregisterFromSystemNotifications];
}

- (void)performScheduledCheck {
    dispatch_async(self.detectionQueue, ^{
        if ([self checkForRecoveryKeyUsage]) {
            os_log_info(self.log, "Scheduled check detected recovery key usage");
        }
        self.lastCheckDate = [NSDate date];
    });
}

#pragma mark - Detection Methods

- (BOOL)checkForRecoveryKeyUsage {
    os_log_debug(self.log, "Checking for recovery key usage");
    
    BOOL detected = NO;
    
    switch (self.detectionMethod) {
        case RecoveryKeyDetectionMethodAuthLog:
            detected = [self checkAuthLog];
            break;
            
        case RecoveryKeyDetectionMethodFDERecovery:
            detected = [self checkFDERecoveryStatus];
            break;
            
        case RecoveryKeyDetectionMethodLoginWindow:
            detected = [self checkLoginWindowEvents];
            break;
            
        case RecoveryKeyDetectionMethodAll:
            detected = [self checkAuthLog] || 
                      [self checkFDERecoveryStatus] || 
                      [self checkLoginWindowEvents];
            break;
            
        default:
            break;
    }
    
    if (detected) {
        [self handleRecoveryKeyUsageDetected];
    }
    
    return detected;
}

- (BOOL)checkAuthLog {
    @autoreleasepool {
        // Check system log for recovery key usage indicators
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/log";
        task.arguments = @[@"show", 
                          @"--predicate", @"eventMessage CONTAINS 'recovery' OR eventMessage CONTAINS 'FileVault'",
                          @"--last", @"1h",
                          @"--style", @"json"];
        
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = [NSPipe pipe];
        
        @try {
            [task launch];
            [task waitUntilExit];
            
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            if (data.length > 0) {
                NSError *error;
                NSArray *logEntries = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                
                if (!error && logEntries) {
                    for (NSDictionary *entry in logEntries) {
                        NSString *message = entry[@"eventMessage"];
                        if ([self isRecoveryKeyUsageMessage:message]) {
                            os_log_info(self.log, "Detected recovery key usage in auth log: %{public}@", message);
                            return YES;
                        }
                    }
                }
            }
        } @catch (NSException *exception) {
            os_log_error(self.log, "Failed to check auth log: %{public}@", exception.reason);
        }
    }
    
    return NO;
}

- (BOOL)checkFDERecoveryStatus {
    // Check FileVault recovery status
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/fdesetup";
    task.arguments = @[@"status"];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        
        // Check if there are indicators of recent recovery key use
        // This is a simplified check - in production, you'd want more sophisticated detection
        if ([output containsString:@"Recovery"]) {
            // Check if we have a recent unlock event that might indicate recovery key use
            return [self checkForRecentUnlockWithRecovery];
        }
    } @catch (NSException *exception) {
        os_log_error(self.log, "Failed to check FDE status: %{public}@", exception.reason);
    }
    
    return NO;
}

- (BOOL)checkLoginWindowEvents {
    // Check for login window events that might indicate recovery key usage
    // This monitors for specific patterns in the login process
    
    @autoreleasepool {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/log";
        task.arguments = @[@"show",
                          @"--predicate", @"process == 'loginwindow' AND eventMessage CONTAINS[c] 'unlock'",
                          @"--last", @"30m",
                          @"--style", @"json"];
        
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = [NSPipe pipe];
        
        @try {
            [task launch];
            [task waitUntilExit];
            
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            if (data.length > 0) {
                NSError *error;
                NSArray *logEntries = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                
                if (!error && logEntries) {
                    // Look for patterns indicating recovery key use
                    for (NSDictionary *entry in logEntries) {
                        if ([self isRecoveryUnlockEvent:entry]) {
                            os_log_info(self.log, "Detected recovery key unlock in login window events");
                            return YES;
                        }
                    }
                }
            }
        } @catch (NSException *exception) {
            os_log_error(self.log, "Failed to check login window events: %{public}@", exception.reason);
        }
    }
    
    return NO;
}

- (BOOL)checkForRecentUnlockWithRecovery {
    // Check if there was a recent unlock that used recovery key
    // This checks for specific patterns in system behavior after recovery key use
    
    NSString *lastBootTime = [self getLastBootTime];
    if (!lastBootTime) {
        return NO;
    }
    
    // Check if we have cached information about this boot session
    NSString *cacheKey = [NSString stringWithFormat:@"boot_%@", lastBootTime];
    if (self.detectionCache[cacheKey]) {
        return [self.detectionCache[cacheKey] boolValue];
    }
    
    // Look for indicators of recovery key use during this boot
    BOOL wasRecoveryUsed = [self checkBootLogForRecoveryKey:lastBootTime];
    
    // Cache the result
    self.detectionCache[cacheKey] = @(wasRecoveryUsed);
    
    return wasRecoveryUsed;
}

- (NSString *)getLastBootTime {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/sysctl";
    task.arguments = @[@"-n", @"kern.boottime"];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        return [output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } @catch (NSException *exception) {
        os_log_error(self.log, "Failed to get boot time: %{public}@", exception.reason);
    }
    
    return nil;
}

- (BOOL)checkBootLogForRecoveryKey:(NSString *)bootTime {
    // Check boot logs for recovery key usage
    // This is a simplified implementation - production would need more sophisticated detection
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/log";
    task.arguments = @[@"show",
                      @"--predicate", @"eventMessage CONTAINS[c] 'recovery' OR eventMessage CONTAINS[c] 'FDERecoveryAgent'",
                      @"--start", bootTime,
                      @"--style", @"json"];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        if (data.length > 0) {
            NSError *error;
            NSArray *logEntries = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            
            if (!error && logEntries && logEntries.count > 0) {
                // Found recovery-related log entries during boot
                return YES;
            }
        }
    } @catch (NSException *exception) {
        os_log_error(self.log, "Failed to check boot log: %{public}@", exception.reason);
    }
    
    return NO;
}

#pragma mark - Helper Methods

- (BOOL)isRecoveryKeyUsageMessage:(NSString *)message {
    if (!message) return NO;
    
    NSArray *indicators = @[
        @"recovery key",
        @"Recovery Key",
        @"RECOVERY KEY",
        @"FDERecoveryAgent",
        @"FileVault recovery",
        @"personal recovery key",
        @"unlock.*recovery",
        @"recovery.*unlock"
    ];
    
    for (NSString *indicator in indicators) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES[c] %@", 
                                  [NSString stringWithFormat:@".*%@.*", indicator]];
        if ([predicate evaluateWithObject:message]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isRecoveryUnlockEvent:(NSDictionary *)event {
    NSString *message = event[@"eventMessage"];
    NSString *process = event[@"processImagePath"];
    
    // Check if this is a login window unlock event that might be recovery key related
    if ([process containsString:@"loginwindow"]) {
        if ([message containsString:@"unlock"] && 
            ([message containsString:@"recovery"] || [message containsString:@"alternate"])) {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - Detection Handling

- (void)handleRecoveryKeyUsageDetected {
    os_log_info(self.log, "Recovery key usage detected - taking action");
    
    self.detectionCount++;
    NSDate *detectionDate = [NSDate date];
    
    // Store detection info
    [[NSUserDefaults standardUserDefaults] setObject:detectionDate 
                                              forKey:@"LastRecoveryKeyUsageDate"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Mark key as used if configured
    if (self.autoMarkAsUsed && self.rotationManager) {
        os_log_info(self.log, "Marking key as used");
        [self.rotationManager markKeyAsUsed];
    }
    
    // Update lifecycle tracker
    if (self.lifecycleTracker) {
        [self.lifecycleTracker recordKeyUsageEvent:@{
            @"type": @"recovery_key_used",
            @"date": detectionDate,
            @"detection_method": @(self.detectionMethod)
        }];
    }
    
    // Post notification
    [[NSNotificationCenter defaultCenter] postNotificationName:RecoveryKeyUsedNotification
                                                        object:self
                                                      userInfo:@{
        RecoveryKeyUsedDateKey: detectionDate,
        RecoveryKeyUsedMethodKey: @(self.detectionMethod)
    }];
    
    // Trigger rotation if configured
    if (self.triggerRotation && self.rotationManager) {
        os_log_info(self.log, "Triggering immediate rotation due to recovery key use");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.rotationManager rotateKeyWithReason:@"Recovery key was used" 
                                            completion:^(BOOL success, NSError *error) {
                if (success) {
                    os_log_info(self.log, "Rotation triggered successfully after recovery key use");
                } else {
                    os_log_error(self.log, "Failed to rotate after recovery key use: %{public}@", 
                                error.localizedDescription);
                }
            }];
        });
    }
}

#pragma mark - System Notifications

- (void)registerForSystemNotifications {
    // Register for wake/unlock notifications to check for recovery key use
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(systemDidWake:)
                                                               name:NSWorkspaceDidWakeNotification
                                                             object:nil];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(screenDidUnlock:)
                                                               name:NSWorkspaceScreensDidWakeNotification
                                                             object:nil];
}

- (void)unregisterFromSystemNotifications {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

- (void)systemDidWake:(NSNotification *)notification {
    os_log_debug(self.log, "System wake detected - checking for recovery key use");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), self.detectionQueue, ^{
        [self checkForRecoveryKeyUsage];
    });
}

- (void)screenDidUnlock:(NSNotification *)notification {
    os_log_debug(self.log, "Screen unlock detected - checking for recovery key use");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), self.detectionQueue, ^{
        [self checkForRecoveryKeyUsage];
    });
}

#pragma mark - Query Methods

- (BOOL)wasRecoveryKeyUsedInCurrentSession {
    NSString *lastBootTime = [self getLastBootTime];
    if (!lastBootTime) {
        return NO;
    }
    
    return [self checkBootLogForRecoveryKey:lastBootTime];
}

- (BOOL)wasRecoveryKeyUsedSinceDate:(NSDate *)date {
    NSDate *lastUsage = [self lastRecoveryKeyUsageDate];
    if (!lastUsage) {
        return NO;
    }
    
    return [lastUsage timeIntervalSinceDate:date] > 0;
}

- (NSDate *)lastRecoveryKeyUsageDate {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"LastRecoveryKeyUsageDate"];
}

@end