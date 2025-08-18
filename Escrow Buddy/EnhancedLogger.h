//
//  EnhancedLogger.h
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
#import <os/log.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, EscrowBuddyLogLevel) {
    EscrowBuddyLogLevelDebug = 0,
    EscrowBuddyLogLevelInfo,
    EscrowBuddyLogLevelDefault,
    EscrowBuddyLogLevelWarning,
    EscrowBuddyLogLevelError,
    EscrowBuddyLogLevelRotation,
    EscrowBuddyLogLevelCompliance,
    EscrowBuddyLogLevelKeyLifecycle,
    EscrowBuddyLogLevelAPI,
    EscrowBuddyLogLevelSecurity
};

typedef NS_ENUM(NSInteger, LogFormat) {
    LogFormatStandard = 0,
    LogFormatJSON,
    LogFormatStructured
};

@interface EnhancedLogger : NSObject

#pragma mark - Singleton

+ (instancetype)sharedLogger;

#pragma mark - Configuration

@property (nonatomic, assign) LogFormat logFormat;
@property (nonatomic, assign) BOOL enableJSONLogging;
@property (nonatomic, assign) BOOL includeTimestamps;
@property (nonatomic, assign) BOOL includeProcessInfo;
@property (nonatomic, assign) BOOL enableFileLogging;
@property (nonatomic, strong) NSString * _Nullable logFilePath;

#pragma mark - Core Logging Methods

- (void)log:(EscrowBuddyLogLevel)level 
    message:(NSString *)message;

- (void)log:(EscrowBuddyLogLevel)level 
    message:(NSString *)message 
     params:(NSDictionary * _Nullable)params;

- (void)log:(EscrowBuddyLogLevel)level 
    message:(NSString *)message 
   category:(NSString *)category;

- (void)log:(EscrowBuddyLogLevel)level 
    message:(NSString *)message 
   category:(NSString *)category 
     params:(NSDictionary * _Nullable)params;

#pragma mark - Specialized Logging

- (void)logRotationEvent:(NSString *)event 
                  reason:(NSString *)reason 
                  keyID:(NSString * _Nullable)keyID;

- (void)logComplianceEvent:(NSString *)event 
                  standard:(NSString *)standard 
                    status:(BOOL)compliant;

- (void)logKeyLifecycleEvent:(NSString *)event 
                        keyID:(NSString *)keyID 
                       status:(NSString *)status;

- (void)logAPICall:(NSString *)endpoint 
            method:(NSString *)method 
          response:(NSInteger)statusCode 
          duration:(NSTimeInterval)duration;

- (void)logSecurityEvent:(NSString *)event 
                severity:(NSString *)severity 
                 details:(NSDictionary * _Nullable)details;

#pragma mark - Convenience Methods

- (void)debug:(NSString *)message;
- (void)info:(NSString *)message;
- (void)warning:(NSString *)message;
- (void)error:(NSString *)message;
- (void)error:(NSString *)message withError:(NSError *)error;

#pragma mark - Structured Logging

- (void)logStructured:(NSDictionary *)logEntry;
- (NSString *)formatAsJSON:(NSDictionary *)logEntry;
- (NSString *)formatAsStructured:(NSDictionary *)logEntry;

#pragma mark - Log File Management

- (BOOL)initializeFileLogging;
- (void)rotateLogFile;
- (void)cleanupOldLogs:(NSInteger)daysToKeep;
- (NSArray *)getRecentLogs:(NSInteger)count;
- (BOOL)exportLogsToPath:(NSString *)path;

#pragma mark - Audit Trail

- (void)recordAuditEvent:(NSString *)action 
                    user:(NSString * _Nullable)user 
                  result:(NSString *)result;

- (NSArray *)getAuditTrail:(NSInteger)days;

#pragma mark - Performance Logging

- (void)startPerformanceTimer:(NSString *)identifier;
- (void)endPerformanceTimer:(NSString *)identifier;
- (NSTimeInterval)getPerformanceTime:(NSString *)identifier;

#pragma mark - Error Tracking

- (void)trackError:(NSError *)error 
           context:(NSString *)context;

- (NSDictionary *)getErrorStatistics;
- (NSArray *)getRecentErrors:(NSInteger)count;

@end

NS_ASSUME_NONNULL_END