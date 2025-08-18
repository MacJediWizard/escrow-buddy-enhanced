//
//  EnhancedLogger.m
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

#import "EnhancedLogger.h"

static NSString *const kLogSubsystem = @"com.netflix.Escrow-Buddy";
static NSString *const kDefaultLogPath = @"/var/log/escrow-buddy.log";
static NSString *const kAuditLogPath = @"/var/log/escrow-buddy-audit.log";

@interface EnhancedLogger ()
@property (nonatomic, strong) os_log_t defaultLog;
@property (nonatomic, strong) NSMutableDictionary *categoryLogs;
@property (nonatomic, strong) NSFileHandle *logFileHandle;
@property (nonatomic, strong) NSFileHandle *auditFileHandle;
@property (nonatomic, strong) NSMutableDictionary *performanceTimers;
@property (nonatomic, strong) NSMutableArray *errorHistory;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSDateFormatter *jsonDateFormatter;
@end

@implementation EnhancedLogger

#pragma mark - Singleton

+ (instancetype)sharedLogger {
    static EnhancedLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaultLog = os_log_create(kLogSubsystem.UTF8String, "General");
        _categoryLogs = [NSMutableDictionary dictionary];
        _performanceTimers = [NSMutableDictionary dictionary];
        _errorHistory = [NSMutableArray array];
        
        _logFormat = LogFormatStandard;
        _enableJSONLogging = NO;
        _includeTimestamps = YES;
        _includeProcessInfo = NO;
        _enableFileLogging = NO;
        _logFilePath = kDefaultLogPath;
        
        [self setupDateFormatters];
        [self createDefaultCategories];
    }
    return self;
}

- (void)setupDateFormatters {
    self.dateFormatter = [[NSDateFormatter alloc] init];
    [self.dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    [self.dateFormatter setTimeZone:[NSTimeZone systemTimeZone]];
    
    self.jsonDateFormatter = [[NSDateFormatter alloc] init];
    [self.jsonDateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
    [self.jsonDateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
}

- (void)createDefaultCategories {
    NSArray *categories = @[@"Rotation", @"Compliance", @"KeyLifecycle", @"API", @"Security", @"Audit"];
    for (NSString *category in categories) {
        self.categoryLogs[category] = os_log_create(kLogSubsystem.UTF8String, category.UTF8String);
    }
}

#pragma mark - Core Logging Methods

- (void)log:(EscrowBuddyLogLevel)level message:(NSString *)message {
    [self log:level message:message category:nil params:nil];
}

- (void)log:(EscrowBuddyLogLevel)level message:(NSString *)message params:(NSDictionary *)params {
    [self log:level message:message category:nil params:params];
}

- (void)log:(EscrowBuddyLogLevel)level message:(NSString *)message category:(NSString *)category {
    [self log:level message:message category:category params:nil];
}

- (void)log:(EscrowBuddyLogLevel)level 
    message:(NSString *)message 
   category:(NSString *)category 
     params:(NSDictionary *)params {
    
    os_log_t log = self.defaultLog;
    if (category && self.categoryLogs[category]) {
        log = self.categoryLogs[category];
    }
    
    NSString *formattedMessage = message;
    
    if (self.enableJSONLogging || self.logFormat == LogFormatJSON) {
        NSDictionary *logEntry = [self createLogEntry:level 
                                              message:message 
                                             category:category 
                                               params:params];
        formattedMessage = [self formatAsJSON:logEntry];
    } else if (self.logFormat == LogFormatStructured) {
        NSDictionary *logEntry = [self createLogEntry:level 
                                              message:message 
                                             category:category 
                                               params:params];
        formattedMessage = [self formatAsStructured:logEntry];
    }
    
    os_log_type_t osLogType = [self osLogTypeForLevel:level];
    os_log_with_type(log, osLogType, "%{public}@", formattedMessage);
    
    if (self.enableFileLogging && self.logFileHandle) {
        [self writeToFile:formattedMessage];
    }
}

- (NSDictionary *)createLogEntry:(EscrowBuddyLogLevel)level 
                         message:(NSString *)message 
                        category:(NSString *)category 
                          params:(NSDictionary *)params {
    
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    
    if (self.includeTimestamps) {
        entry[@"timestamp"] = [self.jsonDateFormatter stringFromDate:[NSDate date]];
    }
    
    entry[@"level"] = [self stringForLevel:level];
    entry[@"message"] = message;
    
    if (category) {
        entry[@"category"] = category;
    }
    
    if (self.includeProcessInfo) {
        entry[@"process"] = [[NSProcessInfo processInfo] processName];
        entry[@"pid"] = @([[NSProcessInfo processInfo] processIdentifier]);
    }
    
    if (params) {
        entry[@"params"] = params;
    }
    
    return entry;
}

- (os_log_type_t)osLogTypeForLevel:(EscrowBuddyLogLevel)level {
    switch (level) {
        case EscrowBuddyLogLevelDebug:
            return OS_LOG_TYPE_DEBUG;
        case EscrowBuddyLogLevelInfo:
            return OS_LOG_TYPE_INFO;
        case EscrowBuddyLogLevelWarning:
        case EscrowBuddyLogLevelCompliance:
            return OS_LOG_TYPE_DEFAULT;
        case EscrowBuddyLogLevelError:
        case EscrowBuddyLogLevelSecurity:
            return OS_LOG_TYPE_ERROR;
        default:
            return OS_LOG_TYPE_DEFAULT;
    }
}

- (NSString *)stringForLevel:(EscrowBuddyLogLevel)level {
    switch (level) {
        case EscrowBuddyLogLevelDebug: return @"DEBUG";
        case EscrowBuddyLogLevelInfo: return @"INFO";
        case EscrowBuddyLogLevelDefault: return @"DEFAULT";
        case EscrowBuddyLogLevelWarning: return @"WARNING";
        case EscrowBuddyLogLevelError: return @"ERROR";
        case EscrowBuddyLogLevelRotation: return @"ROTATION";
        case EscrowBuddyLogLevelCompliance: return @"COMPLIANCE";
        case EscrowBuddyLogLevelKeyLifecycle: return @"KEY_LIFECYCLE";
        case EscrowBuddyLogLevelAPI: return @"API";
        case EscrowBuddyLogLevelSecurity: return @"SECURITY";
        default: return @"UNKNOWN";
    }
}

#pragma mark - Specialized Logging

- (void)logRotationEvent:(NSString *)event reason:(NSString *)reason keyID:(NSString *)keyID {
    NSDictionary *params = @{
        @"event": event,
        @"reason": reason,
        @"keyID": keyID ?: @"unknown"
    };
    
    [self log:EscrowBuddyLogLevelRotation 
      message:[NSString stringWithFormat:@"Rotation Event: %@", event]
     category:@"Rotation"
       params:params];
}

- (void)logComplianceEvent:(NSString *)event standard:(NSString *)standard status:(BOOL)compliant {
    NSDictionary *params = @{
        @"event": event,
        @"standard": standard,
        @"compliant": @(compliant)
    };
    
    [self log:EscrowBuddyLogLevelCompliance
      message:[NSString stringWithFormat:@"Compliance: %@ - %@", event, compliant ? @"PASS" : @"FAIL"]
     category:@"Compliance"
       params:params];
}

- (void)logKeyLifecycleEvent:(NSString *)event keyID:(NSString *)keyID status:(NSString *)status {
    NSDictionary *params = @{
        @"event": event,
        @"keyID": keyID,
        @"status": status
    };
    
    [self log:EscrowBuddyLogLevelKeyLifecycle
      message:[NSString stringWithFormat:@"Key Lifecycle: %@ - %@", event, status]
     category:@"KeyLifecycle"
       params:params];
}

- (void)logAPICall:(NSString *)endpoint method:(NSString *)method response:(NSInteger)statusCode duration:(NSTimeInterval)duration {
    NSDictionary *params = @{
        @"endpoint": endpoint,
        @"method": method,
        @"statusCode": @(statusCode),
        @"duration": @(duration)
    };
    
    NSString *message = [NSString stringWithFormat:@"API Call: %@ %@ - %ld (%.2fms)", 
                        method, endpoint, (long)statusCode, duration * 1000];
    
    [self log:EscrowBuddyLogLevelAPI
      message:message
     category:@"API"
       params:params];
}

- (void)logSecurityEvent:(NSString *)event severity:(NSString *)severity details:(NSDictionary *)details {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"event"] = event;
    params[@"severity"] = severity;
    if (details) {
        params[@"details"] = details;
    }
    
    [self log:EscrowBuddyLogLevelSecurity
      message:[NSString stringWithFormat:@"Security Event: %@ [%@]", event, severity]
     category:@"Security"
       params:params];
}

#pragma mark - Convenience Methods

- (void)debug:(NSString *)message {
    [self log:EscrowBuddyLogLevelDebug message:message];
}

- (void)info:(NSString *)message {
    [self log:EscrowBuddyLogLevelInfo message:message];
}

- (void)warning:(NSString *)message {
    [self log:EscrowBuddyLogLevelWarning message:message];
}

- (void)error:(NSString *)message {
    [self log:EscrowBuddyLogLevelError message:message];
}

- (void)error:(NSString *)message withError:(NSError *)error {
    NSDictionary *params = @{
        @"errorDomain": error.domain,
        @"errorCode": @(error.code),
        @"errorDescription": error.localizedDescription ?: @""
    };
    
    [self log:EscrowBuddyLogLevelError message:message params:params];
    [self trackError:error context:message];
}

#pragma mark - Structured Logging

- (void)logStructured:(NSDictionary *)logEntry {
    NSString *formatted;
    
    if (self.logFormat == LogFormatJSON) {
        formatted = [self formatAsJSON:logEntry];
    } else {
        formatted = [self formatAsStructured:logEntry];
    }
    
    os_log_with_type(self.defaultLog, OS_LOG_TYPE_DEFAULT, "%{public}@", formatted);
    
    if (self.enableFileLogging && self.logFileHandle) {
        [self writeToFile:formatted];
    }
}

- (NSString *)formatAsJSON:(NSDictionary *)logEntry {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:logEntry 
                                                       options:0 
                                                         error:&error];
    if (error) {
        return [NSString stringWithFormat:@"JSON formatting error: %@", error.localizedDescription];
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)formatAsStructured:(NSDictionary *)logEntry {
    NSMutableArray *parts = [NSMutableArray array];
    
    for (NSString *key in logEntry) {
        id value = logEntry[key];
        NSString *valueString;
        
        if ([value isKindOfClass:[NSString class]]) {
            valueString = value;
        } else if ([value isKindOfClass:[NSNumber class]]) {
            valueString = [value stringValue];
        } else if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
            valueString = [self formatAsJSON:value];
        } else {
            valueString = [value description];
        }
        
        [parts addObject:[NSString stringWithFormat:@"%@=\"%@\"", key, valueString]];
    }
    
    return [parts componentsJoinedByString:@" "];
}

#pragma mark - Log File Management

- (BOOL)initializeFileLogging {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:self.logFilePath]) {
        [fileManager createFileAtPath:self.logFilePath contents:nil attributes:nil];
    }
    
    self.logFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.logFilePath];
    [self.logFileHandle seekToEndOfFile];
    
    if (![fileManager fileExistsAtPath:kAuditLogPath]) {
        [fileManager createFileAtPath:kAuditLogPath contents:nil attributes:nil];
    }
    
    self.auditFileHandle = [NSFileHandle fileHandleForWritingAtPath:kAuditLogPath];
    [self.auditFileHandle seekToEndOfFile];
    
    self.enableFileLogging = (self.logFileHandle != nil);
    
    return self.enableFileLogging;
}

- (void)writeToFile:(NSString *)message {
    if (!self.logFileHandle) return;
    
    NSString *timestampedMessage = [NSString stringWithFormat:@"%@ %@\n",
                                   [self.dateFormatter stringFromDate:[NSDate date]],
                                   message];
    
    NSData *data = [timestampedMessage dataUsingEncoding:NSUTF8StringEncoding];
    [self.logFileHandle writeData:data];
    [self.logFileHandle synchronizeFile];
}

- (void)rotateLogFile {
    if (!self.logFileHandle) return;
    
    [self.logFileHandle closeFile];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *archivePath = [NSString stringWithFormat:@"%@.%@",
                           self.logFilePath,
                           [self.dateFormatter stringFromDate:[NSDate date]]];
    
    [fileManager moveItemAtPath:self.logFilePath toPath:archivePath error:nil];
    
    [self initializeFileLogging];
}

- (void)cleanupOldLogs:(NSInteger)daysToKeep {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *logDirectory = [self.logFilePath stringByDeletingLastPathComponent];
    NSArray *files = [fileManager contentsOfDirectoryAtPath:logDirectory error:nil];
    
    NSDate *cutoffDate = [[NSDate date] dateByAddingTimeInterval:-daysToKeep * 86400];
    
    for (NSString *file in files) {
        if ([file hasPrefix:[[self.logFilePath lastPathComponent] stringByDeletingPathExtension]]) {
            NSString *fullPath = [logDirectory stringByAppendingPathComponent:file];
            NSDictionary *attrs = [fileManager attributesOfItemAtPath:fullPath error:nil];
            NSDate *modDate = attrs[NSFileModificationDate];
            
            if ([modDate compare:cutoffDate] == NSOrderedAscending) {
                [fileManager removeItemAtPath:fullPath error:nil];
            }
        }
    }
}

- (NSArray *)getRecentLogs:(NSInteger)count {
    // Implementation would read from log file
    return @[];
}

- (BOOL)exportLogsToPath:(NSString *)path {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    return [fileManager copyItemAtPath:self.logFilePath toPath:path error:&error];
}

#pragma mark - Audit Trail

- (void)recordAuditEvent:(NSString *)action user:(NSString *)user result:(NSString *)result {
    NSDictionary *auditEntry = @{
        @"timestamp": [self.jsonDateFormatter stringFromDate:[NSDate date]],
        @"action": action,
        @"user": user ?: @"system",
        @"result": result,
        @"pid": @([[NSProcessInfo processInfo] processIdentifier])
    };
    
    NSString *auditJSON = [self formatAsJSON:auditEntry];
    
    if (self.auditFileHandle) {
        NSData *data = [[auditJSON stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        [self.auditFileHandle writeData:data];
        [self.auditFileHandle synchronizeFile];
    }
    
    [self log:EscrowBuddyLogLevelDefault 
      message:[NSString stringWithFormat:@"AUDIT: %@ by %@ - %@", action, user ?: @"system", result]
     category:@"Audit"
       params:auditEntry];
}

- (NSArray *)getAuditTrail:(NSInteger)days {
    // Implementation would read from audit log file
    return @[];
}

#pragma mark - Performance Logging

- (void)startPerformanceTimer:(NSString *)identifier {
    self.performanceTimers[identifier] = [NSDate date];
}

- (void)endPerformanceTimer:(NSString *)identifier {
    NSDate *startTime = self.performanceTimers[identifier];
    if (!startTime) return;
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
    
    [self log:EscrowBuddyLogLevelInfo
      message:[NSString stringWithFormat:@"Performance: %@ completed in %.3fs", identifier, duration]
       params:@{@"identifier": identifier, @"duration": @(duration)}];
    
    [self.performanceTimers removeObjectForKey:identifier];
}

- (NSTimeInterval)getPerformanceTime:(NSString *)identifier {
    NSDate *startTime = self.performanceTimers[identifier];
    if (!startTime) return 0;
    
    return [[NSDate date] timeIntervalSinceDate:startTime];
}

#pragma mark - Error Tracking

- (void)trackError:(NSError *)error context:(NSString *)context {
    NSDictionary *errorEntry = @{
        @"timestamp": [NSDate date],
        @"context": context,
        @"domain": error.domain,
        @"code": @(error.code),
        @"description": error.localizedDescription ?: @""
    };
    
    [self.errorHistory addObject:errorEntry];
    
    if (self.errorHistory.count > 100) {
        [self.errorHistory removeObjectAtIndex:0];
    }
}

- (NSDictionary *)getErrorStatistics {
    NSMutableDictionary *stats = [NSMutableDictionary dictionary];
    NSMutableDictionary *domainCounts = [NSMutableDictionary dictionary];
    
    for (NSDictionary *error in self.errorHistory) {
        NSString *domain = error[@"domain"];
        domainCounts[domain] = @([domainCounts[domain] integerValue] + 1);
    }
    
    stats[@"totalErrors"] = @(self.errorHistory.count);
    stats[@"errorsByDomain"] = domainCounts;
    
    return stats;
}

- (NSArray *)getRecentErrors:(NSInteger)count {
    NSInteger startIndex = MAX(0, self.errorHistory.count - count);
    NSRange range = NSMakeRange(startIndex, MIN(count, self.errorHistory.count));
    
    return [self.errorHistory subarrayWithRange:range];
}

@end