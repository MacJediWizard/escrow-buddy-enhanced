//
//  KeyLifecycleTracker.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, KeyStatus) {
    KeyStatusActive = 0,
    KeyStatusUsed,
    KeyStatusExpired,
    KeyStatusRotated,
    KeyStatusInvalid
};

typedef NS_ENUM(NSInteger, KeyEvent) {
    KeyEventCreated = 0,
    KeyEventUsed,
    KeyEventRotated,
    KeyEventExpired,
    KeyEventVerified,
    KeyEventEscrowed,
    KeyEventDeleted
};

@interface KeyMetadata : NSObject
@property (nonatomic, strong) NSString *keyID;
@property (nonatomic, strong) NSDate *createdDate;
@property (nonatomic, strong) NSDate * _Nullable usedDate;
@property (nonatomic, strong) NSDate * _Nullable rotatedDate;
@property (nonatomic, assign) KeyStatus status;
@property (nonatomic, strong) NSString * _Nullable rotationReason;
@property (nonatomic, strong) NSString * _Nullable escrowLocation;
@property (nonatomic, assign) BOOL escrowVerified;
@property (nonatomic, strong) NSMutableArray *events;
@end

@interface KeyLifecycleTracker : NSObject

#pragma mark - Singleton

+ (instancetype)sharedTracker;

#pragma mark - Current Key Management

- (KeyMetadata * _Nullable)getCurrentKey;
- (NSString * _Nullable)getCurrentKeyID;
- (BOOL)createNewKey:(NSString *)keyID;
- (BOOL)updateCurrentKeyStatus:(KeyStatus)status;
- (NSInteger)getCurrentKeyAgeDays;
- (NSDate * _Nullable)getCurrentKeyCreationDate;

#pragma mark - Key Usage Tracking

- (BOOL)markCurrentKeyAsUsed;
- (BOOL)isCurrentKeyUsed;
- (NSDate * _Nullable)getCurrentKeyUsedDate;
- (NSInteger)getDaysSinceLastUse;

#pragma mark - Key Rotation

- (BOOL)rotateKey:(NSString *)newKeyID reason:(NSString *)reason;
- (NSArray<KeyMetadata *> *)getRotationHistory;
- (KeyMetadata * _Nullable)getPreviousKey;
- (NSInteger)getTotalRotationCount;

#pragma mark - Key Age Management

- (BOOL)isKeyExpiredByAge:(NSInteger)maxAgeDays;
- (NSInteger)getDaysUntilExpiration:(NSInteger)maxAgeDays;
- (BOOL)shouldSendExpirationWarning:(NSInteger)warningDays;

#pragma mark - Event Tracking

- (void)recordKeyEvent:(KeyEvent)event forKeyID:(NSString *)keyID;
- (void)recordRotationWithReason:(NSInteger)reason keyID:(NSString *)keyID;
- (void)recordKeyUsageEvent:(NSDictionary *)eventInfo;
- (NSArray *)getEventsForKey:(NSString *)keyID;
- (NSArray *)getAllKeyEvents;
- (void)cleanupOldEvents:(NSInteger)daysToKeep;

#pragma mark - Escrow Management

- (BOOL)markKeyAsEscrowed:(NSString *)keyID location:(NSString *)location;
- (BOOL)verifyKeyEscrow:(NSString *)keyID;
- (BOOL)isCurrentKeyEscrowed;
- (NSString * _Nullable)getCurrentKeyEscrowLocation;

#pragma mark - Storage Management

- (BOOL)saveKeyData;
- (BOOL)loadKeyData;
- (void)clearAllKeyData;
- (NSDictionary *)exportKeyHistory;

#pragma mark - Statistics

- (NSDictionary *)getKeyStatistics;
- (NSInteger)getAverageKeyLifetime;
- (NSInteger)getShortestKeyLifetime;
- (NSInteger)getLongestKeyLifetime;
- (NSDate * _Nullable)getOldestKeyDate;

#pragma mark - Compliance

- (BOOL)isCompliantWithPolicy:(NSString *)policy maxAge:(NSInteger)maxAge;
- (NSArray *)getComplianceViolations:(NSInteger)maxAge;
- (NSDictionary *)generateComplianceReport;

#pragma mark - Maintenance

- (void)performMaintenance;
- (BOOL)archiveOldKeys:(NSInteger)keysToKeep;
- (NSInteger)getDatabaseSize;
- (BOOL)optimizeStorage;

@end

NS_ASSUME_NONNULL_END