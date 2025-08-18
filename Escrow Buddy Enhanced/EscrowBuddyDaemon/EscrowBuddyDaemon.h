//
//  EscrowBuddyDaemon.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DaemonStatus) {
    DaemonStatusIdle = 0,
    DaemonStatusChecking,
    DaemonStatusRotating,
    DaemonStatusError
};

typedef void (^DaemonCompletionHandler)(BOOL success, NSError * _Nullable error);

@protocol EscrowBuddyDaemonDelegate <NSObject>
@optional
- (void)daemonDidStartRotation;
- (void)daemonDidCompleteRotation:(BOOL)success error:(NSError * _Nullable)error;
- (void)daemonStatusChanged:(DaemonStatus)status;
@end

@interface EscrowBuddyDaemon : NSObject

#pragma mark - Singleton

+ (instancetype)sharedDaemon;

#pragma mark - Properties

@property (nonatomic, readonly) DaemonStatus status;
@property (nonatomic, readonly) NSDate * _Nullable lastRotationDate;
@property (nonatomic, readonly) NSDate * _Nullable nextScheduledCheck;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, weak) id<EscrowBuddyDaemonDelegate> delegate;

#pragma mark - Daemon Lifecycle

- (void)startDaemon;
- (void)stopDaemon;
- (void)restartDaemon;
- (BOOL)isDaemonRunning;

#pragma mark - Rotation Operations

- (BOOL)performBackgroundRotation;
- (void)performBackgroundRotationWithCompletion:(DaemonCompletionHandler)completion;
- (BOOL)isRotationNeeded;
- (BOOL)canPerformRotation;

#pragma mark - Scheduling

- (void)scheduleNextRotationCheck;
- (void)scheduleRotationCheckAtDate:(NSDate *)date;
- (void)cancelScheduledRotation;
- (NSTimeInterval)timeUntilNextCheck;

#pragma mark - XPC Communication

- (void)startXPCService;
- (void)stopXPCService;
- (void)handleXPCMessage:(NSDictionary *)message reply:(void(^)(NSDictionary *))reply;

#pragma mark - Configuration

- (void)reloadConfiguration;
- (NSDictionary *)getCurrentConfiguration;
- (BOOL)updateConfiguration:(NSDictionary *)config;

#pragma mark - Status and Monitoring

- (NSDictionary *)getDaemonStatus;
- (NSArray *)getRotationHistory:(NSInteger)count;
- (NSDictionary *)getStatistics;
- (void)performHealthCheck;

#pragma mark - Key Operations

- (BOOL)rotateFileVaultKey;
- (BOOL)verifyCurrentKey;
- (NSString * _Nullable)getCurrentKeyIdentifier;
- (NSInteger)getCurrentKeyAgeDays;

#pragma mark - Logging and Debugging

- (void)enableDebugMode:(BOOL)enable;
- (NSArray *)getRecentLogs:(NSInteger)count;
- (void)clearLogs;

@end

NS_ASSUME_NONNULL_END