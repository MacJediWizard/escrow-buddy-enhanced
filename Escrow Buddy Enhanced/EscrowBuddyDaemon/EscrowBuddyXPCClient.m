//
//  EscrowBuddyXPCClient.m
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

#import "EscrowBuddyXPCClient.h"
#import <os/log.h>

@interface EscrowBuddyXPCClient ()
@property (nonatomic, strong) NSXPCConnection *connection;
@property (nonatomic, strong) id<EscrowBuddyDaemonProtocol> daemonProxy;
@property (nonatomic, strong) os_log_t logger;
@end

@implementation EscrowBuddyXPCClient

+ (instancetype)sharedClient {
    static EscrowBuddyXPCClient *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logger = os_log_create("com.netflix.Escrow-Buddy", "XPCClient");
    }
    return self;
}

- (BOOL)connectToDaemon {
    if (self.connection) {
        return YES;
    }
    
    os_log_info(self.logger, "Connecting to daemon via XPC");
    
    self.connection = [[NSXPCConnection alloc] initWithMachServiceName:@"com.netflix.escrow-buddy.xpc"
                                                               options:NSXPCConnectionPrivileged];
    
    self.connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(EscrowBuddyDaemonProtocol)];
    
    __weak typeof(self) weakSelf = self;
    self.connection.interruptionHandler = ^{
        os_log_error(weakSelf.logger, "XPC connection interrupted");
        weakSelf.connection = nil;
        weakSelf.daemonProxy = nil;
    };
    
    self.connection.invalidationHandler = ^{
        os_log_info(weakSelf.logger, "XPC connection invalidated");
        weakSelf.connection = nil;
        weakSelf.daemonProxy = nil;
    };
    
    [self.connection resume];
    
    self.daemonProxy = [self.connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        os_log_error(weakSelf.logger, "XPC proxy error: %{public}@", error.localizedDescription);
    }];
    
    return self.daemonProxy != nil;
}

- (void)disconnect {
    [self.connection invalidate];
    self.connection = nil;
    self.daemonProxy = nil;
}

- (BOOL)isConnected {
    return self.connection != nil;
}

- (void)checkIfRotationNeeded:(void(^)(BOOL needed, NSString *reason))completion {
    if (![self connectToDaemon]) {
        completion(NO, @"Cannot connect to daemon");
        return;
    }
    
    [self.daemonProxy checkRotationNeededWithReply:completion];
}

- (void)notifyLoginForUser:(NSString *)username {
    if (![self connectToDaemon]) {
        return;
    }
    
    [self.daemonProxy notifyLoginOccurredForUser:username reply:^{
        os_log_info(self.logger, "Notified daemon of login for user: %{public}@", username);
    }];
}

- (void)notifyPluginRotatedKey:(NSDictionary *)rotationInfo {
    if (![self connectToDaemon]) {
        return;
    }
    
    [self.daemonProxy notifyKeyRotatedByPlugin:rotationInfo reply:^{
        os_log_info(self.logger, "Notified daemon of plugin rotation");
    }];
}

- (void)getDaemonStatus:(void(^)(NSDictionary *status))completion {
    if (![self connectToDaemon]) {
        completion(nil);
        return;
    }
    
    [self.daemonProxy getDaemonStatusWithReply:completion];
}

- (BOOL)shouldAuthPluginRotate {
    // Synchronous check for auth plugin to decide if it should rotate
    // This prevents both daemon and plugin from rotating simultaneously
    
    __block BOOL shouldRotate = YES;
    __block BOOL responseReceived = NO;
    
    if (![self connectToDaemon]) {
        // If daemon isn't running, auth plugin should handle rotation
        return YES;
    }
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [self.daemonProxy getDaemonStatusWithReply:^(NSDictionary *status) {
        if (status) {
            // Check if daemon recently rotated or is currently rotating
            NSNumber *daemonStatus = status[@"status"];
            NSDate *lastRotation = status[@"lastRotation"];
            
            if (daemonStatus && daemonStatus.integerValue == 2) { // DaemonStatusRotating
                shouldRotate = NO; // Daemon is currently rotating
            } else if (lastRotation) {
                NSTimeInterval timeSinceRotation = [[NSDate date] timeIntervalSinceDate:lastRotation];
                if (timeSinceRotation < 3600) { // Within last hour
                    shouldRotate = NO; // Daemon recently rotated
                }
            }
        }
        responseReceived = YES;
        dispatch_semaphore_signal(semaphore);
    }];
    
    // Wait up to 2 seconds for response
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC);
    dispatch_semaphore_wait(semaphore, timeout);
    
    if (!responseReceived) {
        // Timeout - assume daemon isn't responding, auth plugin should handle
        return YES;
    }
    
    return shouldRotate;
}

@end