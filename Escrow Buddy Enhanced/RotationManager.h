//
//  RotationManager.h
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

typedef NS_ENUM(NSInteger, RotationReason) {
    RotationReasonNone = 0,
    RotationReasonAge,
    RotationReasonUsed,
    RotationReasonCompliance,
    RotationReasonManual,
    RotationReasonScheduled
};

@interface RotationManager : NSObject

#pragma mark - Singleton

+ (instancetype)sharedManager;

#pragma mark - Key Rotation Decision Methods

- (BOOL)shouldRotateKey;
- (NSDate * _Nullable)getKeyCreationDate;
- (BOOL)isKeyExpired;
- (NSInteger)getKeyAgeDays;
- (RotationReason)getRotationReason;

#pragma mark - Key Rotation Configuration

- (NSInteger)getRotationIntervalDays;
- (BOOL)isAutoRotationEnabled;
- (BOOL)shouldRotateAfterUse;
- (NSInteger)getMaxKeyAge;
- (NSString *)getRotationPolicy;

#pragma mark - Key Status Management

- (BOOL)isKeyMarkedAsUsed;
- (void)markKeyAsUsed;
- (void)resetKeyUsedStatus;

#pragma mark - Compliance Checking

- (BOOL)isComplianceRotationRequired;
- (NSString * _Nullable)getComplianceStandard;
- (BOOL)meetsComplianceRequirements;

#pragma mark - Rotation History

- (void)recordRotation:(RotationReason)reason;
- (NSArray *)getRotationHistory;
- (NSDate * _Nullable)getLastRotationDate;

#pragma mark - Manual Override

- (BOOL)hasManualRotationFlag;
- (void)clearManualRotationFlag;

#pragma mark - Key Rotation Execution

typedef void (^RotationCompletionHandler)(BOOL success, NSError * _Nullable error);

- (void)rotateKeyWithReason:(NSString *)reason 
                  completion:(RotationCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END