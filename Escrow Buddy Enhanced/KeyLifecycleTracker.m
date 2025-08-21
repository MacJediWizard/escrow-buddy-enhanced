//
//  KeyLifecycleTracker.m
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

#import "KeyLifecycleTracker.h"
#import <os/log.h>

static NSString *const kKeyDataPlistPath = @"/var/db/escrow_buddy_keys.plist";
static NSString *const kKeyEventsPlistPath = @"/var/db/escrow_buddy_events.plist";

@implementation KeyMetadata

- (instancetype)init {
    self = [super init];
    if (self) {
        _events = [NSMutableArray array];
        _status = KeyStatusActive;
    }
    return self;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"keyID"] = self.keyID;
    dict[@"createdDate"] = self.createdDate;
    dict[@"status"] = @(self.status);
    dict[@"events"] = self.events;
    dict[@"escrowVerified"] = @(self.escrowVerified);
    
    if (self.usedDate) dict[@"usedDate"] = self.usedDate;
    if (self.rotatedDate) dict[@"rotatedDate"] = self.rotatedDate;
    if (self.rotationReason) dict[@"rotationReason"] = self.rotationReason;
    if (self.escrowLocation) dict[@"escrowLocation"] = self.escrowLocation;
    
    return dict;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    KeyMetadata *metadata = [[KeyMetadata alloc] init];
    metadata.keyID = dict[@"keyID"];
    metadata.createdDate = dict[@"createdDate"];
    metadata.usedDate = dict[@"usedDate"];
    metadata.rotatedDate = dict[@"rotatedDate"];
    metadata.status = [dict[@"status"] integerValue];
    metadata.rotationReason = dict[@"rotationReason"];
    metadata.escrowLocation = dict[@"escrowLocation"];
    metadata.escrowVerified = [dict[@"escrowVerified"] boolValue];
    metadata.events = [dict[@"events"] mutableCopy] ?: [NSMutableArray array];
    
    return metadata;
}

@end

@interface KeyLifecycleTracker ()
@property (nonatomic, strong) KeyMetadata *currentKey;
@property (nonatomic, strong) NSMutableArray<KeyMetadata *> *keyHistory;
@property (nonatomic, strong) NSMutableArray *allEvents;
@property (nonatomic, strong) os_log_t logger;
@end

@implementation KeyLifecycleTracker

#pragma mark - Singleton

+ (instancetype)sharedTracker {
    static KeyLifecycleTracker *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logger = os_log_create("com.netflix.Escrow-Buddy", "KeyLifecycleTracker");
        _keyHistory = [NSMutableArray array];
        _allEvents = [NSMutableArray array];
        [self loadKeyData];
    }
    return self;
}

#pragma mark - Current Key Management

- (KeyMetadata *)getCurrentKey {
    return self.currentKey;
}

- (NSString *)getCurrentKeyID {
    return self.currentKey ? self.currentKey.keyID : nil;
}

- (BOOL)createNewKey:(NSString *)keyID {
    os_log_info(self.logger, "Creating new key with ID: %{public}@", keyID);
    
    if (self.currentKey) {
        self.currentKey.status = KeyStatusRotated;
        self.currentKey.rotatedDate = [NSDate date];
        [self.keyHistory addObject:self.currentKey];
    }
    
    KeyMetadata *newKey = [[KeyMetadata alloc] init];
    newKey.keyID = keyID;
    newKey.createdDate = [NSDate date];
    newKey.status = KeyStatusActive;
    
    self.currentKey = newKey;
    
    [self recordKeyEvent:KeyEventCreated forKeyID:keyID];
    
    return [self saveKeyData];
}

- (BOOL)updateCurrentKeyStatus:(KeyStatus)status {
    if (!self.currentKey) {
        os_log_error(self.logger, "No current key to update status");
        return NO;
    }
    
    os_log_info(self.logger, "Updating current key status to: %ld", (long)status);
    self.currentKey.status = status;
    
    return [self saveKeyData];
}

- (NSInteger)getCurrentKeyAgeDays {
    if (!self.currentKey || !self.currentKey.createdDate) {
        return 0;
    }
    
    NSTimeInterval seconds = [[NSDate date] timeIntervalSinceDate:self.currentKey.createdDate];
    return (NSInteger)(seconds / 86400);
}

- (NSDate *)getCurrentKeyCreationDate {
    return self.currentKey.createdDate;
}

#pragma mark - Key Usage Tracking

- (BOOL)markCurrentKeyAsUsed {
    if (!self.currentKey) {
        os_log_error(self.logger, "No current key to mark as used");
        return NO;
    }
    
    os_log_info(self.logger, "Marking current key as used");
    self.currentKey.usedDate = [NSDate date];
    self.currentKey.status = KeyStatusUsed;
    
    [self recordKeyEvent:KeyEventUsed forKeyID:self.currentKey.keyID];
    
    return [self saveKeyData];
}

- (BOOL)isCurrentKeyUsed {
    return self.currentKey && self.currentKey.usedDate != nil;
}

- (NSDate *)getCurrentKeyUsedDate {
    return self.currentKey.usedDate;
}

- (NSInteger)getDaysSinceLastUse {
    if (!self.currentKey || !self.currentKey.usedDate) {
        return NSIntegerMax;
    }
    
    NSTimeInterval seconds = [[NSDate date] timeIntervalSinceDate:self.currentKey.usedDate];
    return (NSInteger)(seconds / 86400);
}

#pragma mark - Key Rotation

- (BOOL)rotateKey:(NSString *)newKeyID reason:(NSString *)reason {
    os_log_info(self.logger, "Rotating key. New ID: %{public}@, Reason: %{public}@", newKeyID, reason);
    
    if (self.currentKey) {
        self.currentKey.status = KeyStatusRotated;
        self.currentKey.rotatedDate = [NSDate date];
        self.currentKey.rotationReason = reason;
        [self.keyHistory addObject:self.currentKey];
        
        [self recordKeyEvent:KeyEventRotated forKeyID:self.currentKey.keyID];
    }
    
    KeyMetadata *newKey = [[KeyMetadata alloc] init];
    newKey.keyID = newKeyID;
    newKey.createdDate = [NSDate date];
    newKey.status = KeyStatusActive;
    
    self.currentKey = newKey;
    
    [self recordKeyEvent:KeyEventCreated forKeyID:newKeyID];
    
    if (self.keyHistory.count > 100) {
        NSRange rangeToRemove = NSMakeRange(0, self.keyHistory.count - 100);
        [self.keyHistory removeObjectsInRange:rangeToRemove];
    }
    
    return [self saveKeyData];
}

- (NSArray<KeyMetadata *> *)getRotationHistory {
    return [self.keyHistory copy];
}

- (KeyMetadata *)getPreviousKey {
    if (self.keyHistory.count > 0) {
        return [self.keyHistory lastObject];
    }
    return nil;
}

- (NSInteger)getTotalRotationCount {
    return self.keyHistory.count;
}

#pragma mark - Key Age Management

- (BOOL)isKeyExpiredByAge:(NSInteger)maxAgeDays {
    NSInteger currentAge = [self getCurrentKeyAgeDays];
    return currentAge >= maxAgeDays;
}

- (NSInteger)getDaysUntilExpiration:(NSInteger)maxAgeDays {
    NSInteger currentAge = [self getCurrentKeyAgeDays];
    NSInteger daysRemaining = maxAgeDays - currentAge;
    return daysRemaining > 0 ? daysRemaining : 0;
}

- (BOOL)shouldSendExpirationWarning:(NSInteger)warningDays {
    NSInteger daysUntilExpiration = [self getDaysUntilExpiration:365];
    return daysUntilExpiration <= warningDays && daysUntilExpiration > 0;
}

#pragma mark - Event Tracking

- (void)recordKeyEvent:(KeyEvent)event forKeyID:(NSString *)keyID {
    NSMutableDictionary *eventRecord = [NSMutableDictionary dictionary];
    eventRecord[@"event"] = @(event);
    eventRecord[@"keyID"] = keyID;
    eventRecord[@"timestamp"] = [NSDate date];
    
    NSString *eventName = @"Unknown";
    switch (event) {
        case KeyEventCreated: eventName = @"Created"; break;
        case KeyEventUsed: eventName = @"Used"; break;
        case KeyEventRotated: eventName = @"Rotated"; break;
        case KeyEventExpired: eventName = @"Expired"; break;
        case KeyEventVerified: eventName = @"Verified"; break;
        case KeyEventEscrowed: eventName = @"Escrowed"; break;
        case KeyEventDeleted: eventName = @"Deleted"; break;
    }
    eventRecord[@"eventName"] = eventName;
    
    [self.allEvents addObject:eventRecord];
    
    if (self.currentKey && [self.currentKey.keyID isEqualToString:keyID]) {
        [self.currentKey.events addObject:eventRecord];
    }
    
    for (KeyMetadata *key in self.keyHistory) {
        if ([key.keyID isEqualToString:keyID]) {
            [key.events addObject:eventRecord];
            break;
        }
    }
    
    os_log_info(self.logger, "Recorded event %{public}@ for key %{public}@", eventName, keyID);
}

- (void)recordRotationWithReason:(NSInteger)reason keyID:(NSString *)keyID {
    // Record the rotation event
    [self recordKeyEvent:KeyEventRotated forKeyID:keyID];
    
    // Add additional metadata for the rotation
    NSMutableDictionary *rotationInfo = [NSMutableDictionary dictionary];
    rotationInfo[@"type"] = @"rotation";
    rotationInfo[@"reason"] = @(reason);
    rotationInfo[@"keyID"] = keyID;
    rotationInfo[@"timestamp"] = [NSDate date];
    
    NSString *reasonString = @"Unknown";
    switch (reason) {
        case 0: reasonString = @"None"; break;
        case 1: reasonString = @"Age"; break;
        case 2: reasonString = @"Used"; break;
        case 3: reasonString = @"Compliance"; break;
        case 4: reasonString = @"Manual"; break;
        case 5: reasonString = @"Scheduled"; break;
    }
    rotationInfo[@"reasonString"] = reasonString;
    
    [self.allEvents addObject:rotationInfo];
    
    os_log_info(self.logger, "Recorded rotation with reason %{public}@ for key %{public}@", reasonString, keyID);
}

- (void)recordKeyUsageEvent:(NSDictionary *)eventInfo {
    // Record that a recovery key was used
    NSString *keyID = self.currentKey.keyID ?: @"unknown";
    [self recordKeyEvent:KeyEventUsed forKeyID:keyID];
    
    // Add the usage event with additional info
    NSMutableDictionary *usageEvent = [eventInfo mutableCopy];
    if (!usageEvent) {
        usageEvent = [NSMutableDictionary dictionary];
    }
    usageEvent[@"keyID"] = keyID;
    usageEvent[@"timestamp"] = usageEvent[@"date"] ?: [NSDate date];
    
    [self.allEvents addObject:usageEvent];
    
    os_log_info(self.logger, "Recorded key usage event for key %{public}@", keyID);
}

- (NSArray *)getEventsForKey:(NSString *)keyID {
    NSMutableArray *events = [NSMutableArray array];
    
    for (NSDictionary *event in self.allEvents) {
        if ([event[@"keyID"] isEqualToString:keyID]) {
            [events addObject:event];
        }
    }
    
    return events;
}

- (NSArray *)getAllKeyEvents {
    return [self.allEvents copy];
}

- (void)cleanupOldEvents:(NSInteger)daysToKeep {
    NSDate *cutoffDate = [[NSDate date] dateByAddingTimeInterval:-daysToKeep * 86400];
    
    NSMutableArray *eventsToKeep = [NSMutableArray array];
    for (NSDictionary *event in self.allEvents) {
        NSDate *eventDate = event[@"timestamp"];
        if ([eventDate compare:cutoffDate] == NSOrderedDescending) {
            [eventsToKeep addObject:event];
        }
    }
    
    NSInteger removedCount = self.allEvents.count - eventsToKeep.count;
    if (removedCount > 0) {
        os_log_info(self.logger, "Cleaned up %ld old events", (long)removedCount);
        self.allEvents = eventsToKeep;
    }
}

#pragma mark - Escrow Management

- (BOOL)markKeyAsEscrowed:(NSString *)keyID location:(NSString *)location {
    KeyMetadata *key = nil;
    
    if (self.currentKey && [self.currentKey.keyID isEqualToString:keyID]) {
        key = self.currentKey;
    } else {
        for (KeyMetadata *historicKey in self.keyHistory) {
            if ([historicKey.keyID isEqualToString:keyID]) {
                key = historicKey;
                break;
            }
        }
    }
    
    if (!key) {
        os_log_error(self.logger, "Key not found: %{public}@", keyID);
        return NO;
    }
    
    key.escrowLocation = location;
    key.escrowVerified = NO;
    
    [self recordKeyEvent:KeyEventEscrowed forKeyID:keyID];
    
    return [self saveKeyData];
}

- (BOOL)verifyKeyEscrow:(NSString *)keyID {
    KeyMetadata *key = nil;
    
    if (self.currentKey && [self.currentKey.keyID isEqualToString:keyID]) {
        key = self.currentKey;
    } else {
        for (KeyMetadata *historicKey in self.keyHistory) {
            if ([historicKey.keyID isEqualToString:keyID]) {
                key = historicKey;
                break;
            }
        }
    }
    
    if (!key) {
        os_log_error(self.logger, "Key not found: %{public}@", keyID);
        return NO;
    }
    
    key.escrowVerified = YES;
    
    [self recordKeyEvent:KeyEventVerified forKeyID:keyID];
    
    return [self saveKeyData];
}

- (BOOL)isCurrentKeyEscrowed {
    return self.currentKey && self.currentKey.escrowLocation != nil;
}

- (NSString *)getCurrentKeyEscrowLocation {
    return self.currentKey.escrowLocation;
}

#pragma mark - Storage Management

- (BOOL)saveKeyData {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    
    if (self.currentKey) {
        data[@"currentKey"] = [self.currentKey toDictionary];
    }
    
    NSMutableArray *historyArray = [NSMutableArray array];
    for (KeyMetadata *key in self.keyHistory) {
        [historyArray addObject:[key toDictionary]];
    }
    data[@"keyHistory"] = historyArray;
    
    BOOL keyDataSaved = [data writeToFile:kKeyDataPlistPath atomically:YES];
    BOOL eventsSaved = [self.allEvents writeToFile:kKeyEventsPlistPath atomically:YES];
    
    if (!keyDataSaved) {
        os_log_error(self.logger, "Failed to save key data");
    }
    if (!eventsSaved) {
        os_log_error(self.logger, "Failed to save events");
    }
    
    return keyDataSaved && eventsSaved;
}

- (BOOL)loadKeyData {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kKeyDataPlistPath]) {
        NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:kKeyDataPlistPath];
        if (data) {
            if (data[@"currentKey"]) {
                self.currentKey = [KeyMetadata fromDictionary:data[@"currentKey"]];
            }
            
            NSArray *historyArray = data[@"keyHistory"];
            if (historyArray) {
                self.keyHistory = [NSMutableArray array];
                for (NSDictionary *keyDict in historyArray) {
                    [self.keyHistory addObject:[KeyMetadata fromDictionary:keyDict]];
                }
            }
        }
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:kKeyEventsPlistPath]) {
        NSArray *events = [NSArray arrayWithContentsOfFile:kKeyEventsPlistPath];
        if (events) {
            self.allEvents = [events mutableCopy];
        }
    }
    
    return YES;
}

- (void)clearAllKeyData {
    os_log_info(self.logger, "Clearing all key data");
    
    self.currentKey = nil;
    [self.keyHistory removeAllObjects];
    [self.allEvents removeAllObjects];
    
    [[NSFileManager defaultManager] removeItemAtPath:kKeyDataPlistPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:kKeyEventsPlistPath error:nil];
}

- (NSDictionary *)exportKeyHistory {
    NSMutableDictionary *export = [NSMutableDictionary dictionary];
    
    if (self.currentKey) {
        export[@"currentKey"] = [self.currentKey toDictionary];
    }
    
    NSMutableArray *historyArray = [NSMutableArray array];
    for (KeyMetadata *key in self.keyHistory) {
        [historyArray addObject:[key toDictionary]];
    }
    export[@"keyHistory"] = historyArray;
    export[@"events"] = self.allEvents;
    export[@"exportDate"] = [NSDate date];
    
    return export;
}

#pragma mark - Statistics

- (NSDictionary *)getKeyStatistics {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    
    stats[@"totalKeys"] = @(self.keyHistory.count + (self.currentKey ? 1 : 0));
    stats[@"totalRotations"] = @(self.keyHistory.count);
    stats[@"currentKeyAge"] = @([self getCurrentKeyAgeDays]);
    stats[@"averageLifetime"] = @([self getAverageKeyLifetime]);
    stats[@"shortestLifetime"] = @([self getShortestKeyLifetime]);
    stats[@"longestLifetime"] = @([self getLongestKeyLifetime]);
    
    NSInteger usedCount = 0;
    for (KeyMetadata *key in self.keyHistory) {
        if (key.usedDate) usedCount++;
    }
    if (self.currentKey && self.currentKey.usedDate) usedCount++;
    
    stats[@"keysUsed"] = @(usedCount);
    stats[@"totalEvents"] = @(self.allEvents.count);
    
    return stats;
}

- (NSInteger)getAverageKeyLifetime {
    if (self.keyHistory.count == 0) {
        return [self getCurrentKeyAgeDays];
    }
    
    NSInteger totalDays = 0;
    NSInteger count = 0;
    
    for (KeyMetadata *key in self.keyHistory) {
        if (key.createdDate && key.rotatedDate) {
            NSTimeInterval seconds = [key.rotatedDate timeIntervalSinceDate:key.createdDate];
            totalDays += (NSInteger)(seconds / 86400);
            count++;
        }
    }
    
    if (count == 0) return 0;
    return totalDays / count;
}

- (NSInteger)getShortestKeyLifetime {
    NSInteger shortest = NSIntegerMax;
    
    for (KeyMetadata *key in self.keyHistory) {
        if (key.createdDate && key.rotatedDate) {
            NSTimeInterval seconds = [key.rotatedDate timeIntervalSinceDate:key.createdDate];
            NSInteger days = (NSInteger)(seconds / 86400);
            if (days < shortest) shortest = days;
        }
    }
    
    return shortest == NSIntegerMax ? 0 : shortest;
}

- (NSInteger)getLongestKeyLifetime {
    NSInteger longest = 0;
    
    for (KeyMetadata *key in self.keyHistory) {
        if (key.createdDate && key.rotatedDate) {
            NSTimeInterval seconds = [key.rotatedDate timeIntervalSinceDate:key.createdDate];
            NSInteger days = (NSInteger)(seconds / 86400);
            if (days > longest) longest = days;
        }
    }
    
    NSInteger currentAge = [self getCurrentKeyAgeDays];
    if (currentAge > longest) longest = currentAge;
    
    return longest;
}

- (NSDate *)getOldestKeyDate {
    NSDate *oldest = nil;
    
    for (KeyMetadata *key in self.keyHistory) {
        if (!oldest || [key.createdDate compare:oldest] == NSOrderedAscending) {
            oldest = key.createdDate;
        }
    }
    
    if (self.currentKey && (!oldest || [self.currentKey.createdDate compare:oldest] == NSOrderedAscending)) {
        oldest = self.currentKey.createdDate;
    }
    
    return oldest;
}

#pragma mark - Compliance

- (BOOL)isCompliantWithPolicy:(NSString *)policy maxAge:(NSInteger)maxAge {
    NSInteger currentAge = [self getCurrentKeyAgeDays];
    
    if ([policy isEqualToString:@"NIST"]) {
        return currentAge <= 90;
    } else if ([policy isEqualToString:@"ISO27001"]) {
        return currentAge <= 180;
    } else if ([policy isEqualToString:@"PCI-DSS"]) {
        return currentAge <= 90;
    } else {
        return currentAge <= maxAge;
    }
}

- (NSArray *)getComplianceViolations:(NSInteger)maxAge {
    NSMutableArray *violations = [NSMutableArray array];
    
    NSInteger currentAge = [self getCurrentKeyAgeDays];
    if (currentAge > maxAge) {
        [violations addObject:@{
            @"type": @"KeyAgeViolation",
            @"keyID": self.currentKey.keyID ?: @"Unknown",
            @"age": @(currentAge),
            @"maxAge": @(maxAge)
        }];
    }
    
    if (!self.currentKey || !self.currentKey.escrowVerified) {
        [violations addObject:@{
            @"type": @"EscrowVerificationMissing",
            @"keyID": self.currentKey.keyID ?: @"Unknown"
        }];
    }
    
    return violations;
}

- (NSDictionary *)generateComplianceReport {
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    
    report[@"reportDate"] = [NSDate date];
    report[@"currentKeyAge"] = @([self getCurrentKeyAgeDays]);
    report[@"isEscrowed"] = @([self isCurrentKeyEscrowed]);
    report[@"escrowVerified"] = @(self.currentKey.escrowVerified);
    report[@"totalRotations"] = @(self.keyHistory.count);
    report[@"averageKeyLifetime"] = @([self getAverageKeyLifetime]);
    
    NSArray *violations90 = [self getComplianceViolations:90];
    NSArray *violations180 = [self getComplianceViolations:180];
    NSArray *violations365 = [self getComplianceViolations:365];
    
    report[@"NIST_Compliant"] = @(violations90.count == 0);
    report[@"ISO27001_Compliant"] = @(violations180.count == 0);
    report[@"Standard_Compliant"] = @(violations365.count == 0);
    
    return report;
}

#pragma mark - Maintenance

- (void)performMaintenance {
    os_log_info(self.logger, "Performing maintenance");
    
    [self cleanupOldEvents:365];
    
    [self archiveOldKeys:50];
    
    [self optimizeStorage];
}

- (BOOL)archiveOldKeys:(NSInteger)keysToKeep {
    if (self.keyHistory.count <= keysToKeep) {
        return YES;
    }
    
    NSInteger keysToRemove = self.keyHistory.count - keysToKeep;
    NSRange rangeToRemove = NSMakeRange(0, keysToRemove);
    
    os_log_info(self.logger, "Archiving %ld old keys", (long)keysToRemove);
    
    [self.keyHistory removeObjectsInRange:rangeToRemove];
    
    return [self saveKeyData];
}

- (NSInteger)getDatabaseSize {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    NSDictionary *keyDataAttrs = [fm attributesOfItemAtPath:kKeyDataPlistPath error:&error];
    NSDictionary *eventsAttrs = [fm attributesOfItemAtPath:kKeyEventsPlistPath error:&error];
    
    NSInteger keyDataSize = [keyDataAttrs[NSFileSize] integerValue];
    NSInteger eventsSize = [eventsAttrs[NSFileSize] integerValue];
    
    return keyDataSize + eventsSize;
}

- (BOOL)optimizeStorage {
    [self cleanupOldEvents:365];
    
    [self archiveOldKeys:50];
    
    return [self saveKeyData];
}

@end