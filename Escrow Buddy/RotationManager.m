//
//  RotationManager.m
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

#import "RotationManager.h"
#import <os/log.h>

static NSString *const kRotationManagerDomain = @"com.netflix.Escrow-Buddy";
static NSString *const kKeyLifecyclePlistPath = @"/var/db/escrow_buddy_lifecycle.plist";
static NSString *const kRotationHistoryPlistPath = @"/var/db/escrow_buddy_history.plist";

@interface RotationManager ()
@property (nonatomic, strong) NSMutableDictionary *keyLifecycleData;
@property (nonatomic, strong) NSMutableArray *rotationHistory;
@property (nonatomic, strong) os_log_t logger;
@end

@implementation RotationManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static RotationManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logger = os_log_create("com.netflix.Escrow-Buddy", "RotationManager");
        [self loadKeyLifecycleData];
        [self loadRotationHistory];
    }
    return self;
}

#pragma mark - Data Management

- (void)loadKeyLifecycleData {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kKeyLifecyclePlistPath]) {
        self.keyLifecycleData = [NSMutableDictionary dictionaryWithContentsOfFile:kKeyLifecyclePlistPath];
    }
    
    if (!self.keyLifecycleData) {
        self.keyLifecycleData = [NSMutableDictionary dictionary];
        os_log_info(self.logger, "Initialized empty key lifecycle data");
    }
}

- (void)loadRotationHistory {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kRotationHistoryPlistPath]) {
        self.rotationHistory = [NSMutableArray arrayWithContentsOfFile:kRotationHistoryPlistPath];
    }
    
    if (!self.rotationHistory) {
        self.rotationHistory = [NSMutableArray array];
        os_log_info(self.logger, "Initialized empty rotation history");
    }
}

- (void)saveKeyLifecycleData {
    BOOL success = [self.keyLifecycleData writeToFile:kKeyLifecyclePlistPath atomically:YES];
    if (!success) {
        os_log_error(self.logger, "Failed to save key lifecycle data");
    }
}

- (void)saveRotationHistory {
    BOOL success = [self.rotationHistory writeToFile:kRotationHistoryPlistPath atomically:YES];
    if (!success) {
        os_log_error(self.logger, "Failed to save rotation history");
    }
}

#pragma mark - Key Rotation Decision Methods

- (BOOL)shouldRotateKey {
    os_log_info(self.logger, "Evaluating if key rotation is needed");
    
    if (![self isAutoRotationEnabled]) {
        os_log_info(self.logger, "Auto-rotation is disabled");
        return [self hasManualRotationFlag];
    }
    
    if ([self hasManualRotationFlag]) {
        os_log_info(self.logger, "Manual rotation flag is set");
        return YES;
    }
    
    if ([self isKeyExpired]) {
        os_log_info(self.logger, "Key has expired based on age");
        return YES;
    }
    
    if ([self shouldRotateAfterUse] && [self isKeyMarkedAsUsed]) {
        os_log_info(self.logger, "Key is marked as used and rotation after use is enabled");
        return YES;
    }
    
    if ([self isComplianceRotationRequired]) {
        os_log_info(self.logger, "Compliance policy requires rotation");
        return YES;
    }
    
    os_log_info(self.logger, "No rotation needed at this time");
    return NO;
}

- (NSDate *)getKeyCreationDate {
    NSDictionary *currentKey = self.keyLifecycleData[@"currentKey"];
    if (currentKey && currentKey[@"created"]) {
        return currentKey[@"created"];
    }
    return nil;
}

- (BOOL)isKeyExpired {
    NSDate *creationDate = [self getKeyCreationDate];
    if (!creationDate) {
        os_log_info(self.logger, "No key creation date found, assuming new key needed");
        return YES;
    }
    
    NSInteger keyAge = [self getKeyAgeDays];
    NSInteger maxAge = [self getMaxKeyAge];
    
    BOOL expired = (keyAge >= maxAge);
    os_log_info(self.logger, "Key age: %ld days, Max age: %ld days, Expired: %d", 
                (long)keyAge, (long)maxAge, expired);
    
    return expired;
}

- (NSInteger)getKeyAgeDays {
    NSDate *creationDate = [self getKeyCreationDate];
    if (!creationDate) {
        return NSIntegerMax;
    }
    
    NSTimeInterval secondsSinceCreation = [[NSDate date] timeIntervalSinceDate:creationDate];
    NSInteger days = (NSInteger)(secondsSinceCreation / 86400);
    
    return days;
}

- (RotationReason)getRotationReason {
    if ([self hasManualRotationFlag]) {
        return RotationReasonManual;
    }
    
    if ([self isKeyExpired]) {
        return RotationReasonAge;
    }
    
    if ([self shouldRotateAfterUse] && [self isKeyMarkedAsUsed]) {
        return RotationReasonUsed;
    }
    
    if ([self isComplianceRotationRequired]) {
        return RotationReasonCompliance;
    }
    
    NSInteger intervalDays = [self getRotationIntervalDays];
    if (intervalDays > 0 && [self getKeyAgeDays] >= intervalDays) {
        return RotationReasonScheduled;
    }
    
    return RotationReasonNone;
}

#pragma mark - Key Rotation Configuration

- (NSInteger)getRotationIntervalDays {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("RotationIntervalDays"), 
                                                        (__bridge CFStringRef)kRotationManagerDomain);
    if (value) {
        NSInteger days = [(__bridge NSNumber *)value integerValue];
        CFRelease(value);
        return days;
    }
    return 90;
}

- (BOOL)isAutoRotationEnabled {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("AutoRotationEnabled"), 
                                                        (__bridge CFStringRef)kRotationManagerDomain);
    if (value) {
        BOOL enabled = [(__bridge NSNumber *)value boolValue];
        CFRelease(value);
        return enabled;
    }
    return NO;
}

- (BOOL)shouldRotateAfterUse {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("RotateAfterUse"), 
                                                        (__bridge CFStringRef)kRotationManagerDomain);
    if (value) {
        BOOL rotateAfterUse = [(__bridge NSNumber *)value boolValue];
        CFRelease(value);
        return rotateAfterUse;
    }
    return NO;
}

- (NSInteger)getMaxKeyAge {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("MaxKeyAge"), 
                                                        (__bridge CFStringRef)kRotationManagerDomain);
    if (value) {
        NSInteger maxAge = [(__bridge NSNumber *)value integerValue];
        CFRelease(value);
        return maxAge;
    }
    return 365;
}

- (NSString *)getRotationPolicy {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("RotationPolicy"), 
                                                        (__bridge CFStringRef)kRotationManagerDomain);
    if (value) {
        NSString *policy = (__bridge NSString *)value;
        CFRelease(value);
        return policy;
    }
    return @"standard";
}

#pragma mark - Key Status Management

- (BOOL)isKeyMarkedAsUsed {
    NSDictionary *currentKey = self.keyLifecycleData[@"currentKey"];
    if (currentKey && currentKey[@"used"]) {
        return [currentKey[@"used"] boolValue];
    }
    return NO;
}

- (void)markKeyAsUsed {
    os_log_info(self.logger, "Marking current key as used");
    
    NSMutableDictionary *currentKey = [self.keyLifecycleData[@"currentKey"] mutableCopy];
    if (!currentKey) {
        currentKey = [NSMutableDictionary dictionary];
    }
    
    currentKey[@"used"] = @YES;
    currentKey[@"usedDate"] = [NSDate date];
    
    self.keyLifecycleData[@"currentKey"] = currentKey;
    [self saveKeyLifecycleData];
}

- (void)resetKeyUsedStatus {
    os_log_info(self.logger, "Resetting key used status");
    
    NSMutableDictionary *currentKey = [self.keyLifecycleData[@"currentKey"] mutableCopy];
    if (currentKey) {
        currentKey[@"used"] = @NO;
        [currentKey removeObjectForKey:@"usedDate"];
        self.keyLifecycleData[@"currentKey"] = currentKey;
        [self saveKeyLifecycleData];
    }
}

#pragma mark - Compliance Checking

- (BOOL)isComplianceRotationRequired {
    NSString *standard = [self getComplianceStandard];
    if (!standard || [standard isEqualToString:@"none"]) {
        return NO;
    }
    
    if ([standard isEqualToString:@"NIST"]) {
        return [self getKeyAgeDays] >= 90;
    } else if ([standard isEqualToString:@"ISO27001"]) {
        return [self getKeyAgeDays] >= 180;
    } else if ([standard isEqualToString:@"PCI-DSS"]) {
        return [self getKeyAgeDays] >= 90;
    }
    
    return NO;
}

- (NSString *)getComplianceStandard {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("ComplianceStandard"), 
                                                        (__bridge CFStringRef)kRotationManagerDomain);
    if (value) {
        NSString *standard = (__bridge NSString *)value;
        CFRelease(value);
        return standard;
    }
    return @"none";
}

- (BOOL)meetsComplianceRequirements {
    NSString *standard = [self getComplianceStandard];
    if (!standard || [standard isEqualToString:@"none"]) {
        return YES;
    }
    
    NSInteger keyAge = [self getKeyAgeDays];
    
    if ([standard isEqualToString:@"NIST"]) {
        return keyAge < 90;
    } else if ([standard isEqualToString:@"ISO27001"]) {
        return keyAge < 180;
    } else if ([standard isEqualToString:@"PCI-DSS"]) {
        return keyAge < 90;
    }
    
    return YES;
}

#pragma mark - Rotation History

- (void)recordRotation:(RotationReason)reason {
    os_log_info(self.logger, "Recording rotation with reason: %ld", (long)reason);
    
    NSMutableDictionary *rotationRecord = [NSMutableDictionary dictionary];
    rotationRecord[@"date"] = [NSDate date];
    rotationRecord[@"reason"] = @(reason);
    
    NSString *reasonString = @"Unknown";
    switch (reason) {
        case RotationReasonAge:
            reasonString = @"Age-based rotation";
            break;
        case RotationReasonUsed:
            reasonString = @"Key was used";
            break;
        case RotationReasonCompliance:
            reasonString = @"Compliance requirement";
            break;
        case RotationReasonManual:
            reasonString = @"Manual rotation";
            break;
        case RotationReasonScheduled:
            reasonString = @"Scheduled rotation";
            break;
        default:
            break;
    }
    rotationRecord[@"reasonString"] = reasonString;
    
    NSDictionary *oldKey = self.keyLifecycleData[@"currentKey"];
    if (oldKey) {
        rotationRecord[@"previousKey"] = oldKey;
    }
    
    [self.rotationHistory addObject:rotationRecord];
    
    if (self.rotationHistory.count > 100) {
        [self.rotationHistory removeObjectAtIndex:0];
    }
    
    [self saveRotationHistory];
    
    NSMutableDictionary *newKey = [NSMutableDictionary dictionary];
    newKey[@"created"] = [NSDate date];
    newKey[@"keyID"] = [[NSUUID UUID] UUIDString];
    newKey[@"used"] = @NO;
    newKey[@"rotationReason"] = reasonString;
    
    self.keyLifecycleData[@"currentKey"] = newKey;
    [self saveKeyLifecycleData];
}

- (NSArray *)getRotationHistory {
    return [self.rotationHistory copy];
}

- (NSDate *)getLastRotationDate {
    if (self.rotationHistory.count > 0) {
        NSDictionary *lastRotation = [self.rotationHistory lastObject];
        return lastRotation[@"date"];
    }
    return nil;
}

#pragma mark - Manual Override

- (BOOL)hasManualRotationFlag {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("GenerateNewKey"), 
                                                        (__bridge CFStringRef)kRotationManagerDomain);
    if (value) {
        BOOL flag = [(__bridge NSNumber *)value boolValue];
        CFRelease(value);
        return flag;
    }
    return NO;
}

- (void)clearManualRotationFlag {
    os_log_info(self.logger, "Clearing manual rotation flag");
    CFPreferencesSetValue(CFSTR("GenerateNewKey"), 
                         (__bridge CFPropertyListRef)@NO,
                         (__bridge CFStringRef)kRotationManagerDomain,
                         kCFPreferencesAnyUser,
                         kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kRotationManagerDomain);
}

@end