//
//  EscrowBuddyXPCProtocol.h
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

// XPC Service Protocol for communication between daemon and auth plugin
@protocol EscrowBuddyDaemonProtocol <NSObject>

@required

// Status and Information
- (void)getDaemonStatusWithReply:(void (^)(NSDictionary *status))reply;
- (void)getKeyInfoWithReply:(void (^)(NSDictionary *keyInfo))reply;
- (void)getRotationHistoryWithCount:(NSInteger)count reply:(void (^)(NSArray *history))reply;

// Rotation Operations
- (void)checkRotationNeededWithReply:(void (^)(BOOL needed, NSString * _Nullable reason))reply;
- (void)performRotationWithReply:(void (^)(BOOL success, NSError * _Nullable error))reply;
- (void)scheduleRotationAtDate:(NSDate *)date reply:(void (^)(BOOL scheduled))reply;
- (void)cancelScheduledRotationWithReply:(void (^)(BOOL cancelled))reply;

// Configuration
- (void)getConfigurationWithReply:(void (^)(NSDictionary *config))reply;
- (void)updateConfiguration:(NSDictionary *)config reply:(void (^)(BOOL success, NSError * _Nullable error))reply;
- (void)reloadConfigurationWithReply:(void (^)(BOOL success))reply;

// Coordination
- (void)notifyLoginOccurredForUser:(NSString *)username reply:(void (^)(void))reply;
- (void)notifyLogoutOccurredForUser:(NSString *)username reply:(void (^)(void))reply;
- (void)notifyKeyRotatedByPlugin:(NSDictionary *)rotationInfo reply:(void (^)(void))reply;

// Health and Diagnostics
- (void)performHealthCheckWithReply:(void (^)(NSDictionary *health))reply;
- (void)getStatisticsWithReply:(void (^)(NSDictionary *stats))reply;
- (void)getDiagnosticsWithReply:(void (^)(NSDictionary *diagnostics))reply;

@optional

// Advanced Operations
- (void)forceRotationWithCredentials:(NSDictionary *)credentials reply:(void (^)(BOOL success, NSError * _Nullable error))reply;
- (void)verifyKeyEscrowWithReply:(void (^)(BOOL verified, NSError * _Nullable error))reply;
- (void)generateComplianceReportWithReply:(void (^)(NSDictionary * _Nullable report, NSError * _Nullable error))reply;

@end

// XPC Client Protocol for callbacks from daemon to auth plugin
@protocol EscrowBuddyClientProtocol <NSObject>

@optional

// Notifications from daemon
- (void)daemonDidStartRotation;
- (void)daemonDidCompleteRotation:(BOOL)success error:(NSError * _Nullable)error;
- (void)daemonStatusChanged:(NSDictionary *)newStatus;
- (void)daemonConfigurationChanged:(NSDictionary *)newConfig;

@end

NS_ASSUME_NONNULL_END