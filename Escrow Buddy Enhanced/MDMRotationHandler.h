//
//  MDMRotationHandler.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MDMType) {
    MDMTypeJamfPro = 0,      // Uses Jamf binary
    MDMTypeGeneric,          // Generic MDM
    MDMTypeCustom            // Custom script
};

typedef void(^MDMRotationCompletionHandler)(BOOL success, NSString * _Nullable newKeyID, NSError * _Nullable error);

@interface MDMRotationHandler : NSObject

+ (instancetype)sharedHandler;

// MDM-based rotation using Jamf binary
- (BOOL)canPerformMDMRotation;
- (void)performMDMRotationWithCompletion:(MDMRotationCompletionHandler)completion;

// MDM communication
- (void)notifyMDMRotationNeeded;

// Configuration
@property (nonatomic, assign) MDMType mdmType;
@property (nonatomic, assign) BOOL useMDMEscrow;

// Status
- (NSDate * _Nullable)lastSuccessfulRotation;
- (BOOL)isRotationInProgress;

@end

NS_ASSUME_NONNULL_END