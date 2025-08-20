//
//  ComplianceReporter.m
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

#import "ComplianceReporter.h"
#import "KeyLifecycleTracker.h"
#import "RotationManager.h"
#import "ConfigurationManager.h"
#import "EnhancedLogger.h"

static NSString *const kComplianceReportPath = @"/var/db/escrow_buddy_compliance";
static NSString *const kViolationHistoryPath = @"/var/db/escrow_buddy_violations.plist";

@implementation ComplianceReport

- (instancetype)init {
    self = [super init];
    if (self) {
        _generatedDate = [NSDate date];
        _reportID = [[NSUUID UUID] UUIDString];
        _status = ComplianceStatusUnknown;
        _findings = @{};
        _violations = @[];
        _recommendations = @[];
        _metrics = @{};
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"reportID": self.reportID,
        @"generatedDate": self.generatedDate,
        @"standard": @(self.standard),
        @"status": @(self.status),
        @"findings": self.findings,
        @"violations": self.violations,
        @"recommendations": self.recommendations,
        @"metrics": self.metrics
    };
}

@end

@interface ComplianceReporter ()
@property (nonatomic, strong) NSMutableArray<ComplianceReport *> *reportHistory;
@property (nonatomic, strong) NSMutableArray *violationHistory;
@property (nonatomic, strong) NSTimer *scheduledReportTimer;
@property (nonatomic, strong) KeyLifecycleTracker *lifecycleTracker;
@property (nonatomic, strong) RotationManager *rotationManager;
@property (nonatomic, strong) ConfigurationManager *configManager;
@property (nonatomic, strong) EnhancedLogger *logger;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@end

@implementation ComplianceReporter

#pragma mark - Singleton

+ (instancetype)sharedReporter {
    static ComplianceReporter *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _reportHistory = [NSMutableArray array];
        _violationHistory = [NSMutableArray array];
        _lifecycleTracker = [KeyLifecycleTracker sharedTracker];
        _rotationManager = [RotationManager sharedManager];
        _configManager = [ConfigurationManager sharedManager];
        _logger = [EnhancedLogger sharedLogger];
        _reportStoragePath = kComplianceReportPath;
        _reportingIntervalDays = 30;
        _enabledStandards = @[@(ComplianceStandardNIST)];
        
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        
        [self loadViolationHistory];
        [self createReportDirectory];
    }
    return self;
}

- (void)createReportDirectory {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:self.reportStoragePath]) {
        NSError *error;
        [fileManager createDirectoryAtPath:self.reportStoragePath 
               withIntermediateDirectories:YES 
                                attributes:nil 
                                     error:&error];
        if (error) {
            [self.logger error:@"Failed to create compliance report directory" withError:error];
        }
    }
}

- (void)loadViolationHistory {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kViolationHistoryPath]) {
        NSArray *history = [NSArray arrayWithContentsOfFile:kViolationHistoryPath];
        if (history) {
            self.violationHistory = [history mutableCopy];
        }
    }
}

- (void)saveViolationHistory {
    [self.violationHistory writeToFile:kViolationHistoryPath atomically:YES];
}

#pragma mark - Compliance Checking

- (ComplianceStatus)checkCompliance {
    ComplianceStatus worstStatus = ComplianceStatusCompliant;
    
    for (NSNumber *standardNum in self.enabledStandards) {
        ComplianceStandard standard = [standardNum integerValue];
        ComplianceStatus status = [self checkComplianceForStandard:standard];
        
        if (status > worstStatus) {
            worstStatus = status;
        }
    }
    
    [self.logger logComplianceEvent:@"Compliance Check" 
                           standard:[ComplianceReporter stringForStandard:self.primaryStandard] 
                             status:(worstStatus == ComplianceStatusCompliant)];
    
    return worstStatus;
}

- (ComplianceStatus)checkComplianceForStandard:(ComplianceStandard)standard {
    switch (standard) {
        case ComplianceStandardNIST:
            return [self checkNISTCompliance];
        case ComplianceStandardISO27001:
            return [self checkISO27001Compliance];
        case ComplianceStandardPCIDSS:
            return [self checkPCIDSSCompliance];
        case ComplianceStandardHIPAA:
            return [self checkHIPAACompliance];
        case ComplianceStandardSOC2:
            return [self checkSOC2Compliance];
        default:
            return ComplianceStatusUnknown;
    }
}

- (NSDictionary *)performComplianceAudit {
    NSMutableDictionary *audit = [NSMutableDictionary dictionary];
    
    audit[@"auditDate"] = [NSDate date];
    // Get system info
    NSMutableDictionary *systemInfo = [NSMutableDictionary dictionary];
    systemInfo[@"hostname"] = [[NSProcessInfo processInfo] hostName];
    systemInfo[@"osVersion"] = [[NSProcessInfo processInfo] operatingSystemVersionString];
    systemInfo[@"timestamp"] = [NSDate date];
    audit[@"systemInfo"] = systemInfo;
    
    NSMutableDictionary *standardResults = [NSMutableDictionary dictionary];
    
    for (NSNumber *standardNum in self.enabledStandards) {
        ComplianceStandard standard = [standardNum integerValue];
        NSString *standardName = [ComplianceReporter stringForStandard:standard];
        
        ComplianceStatus status = [self checkComplianceForStandard:standard];
        NSDictionary *metrics = [self getMetricsForStandard:standard];
        
        standardResults[standardName] = @{
            @"status": [ComplianceReporter stringForStatus:status],
            @"compliant": @(status == ComplianceStatusCompliant),
            @"metrics": metrics
        };
    }
    
    audit[@"standards"] = standardResults;
    audit[@"overallCompliant"] = @([self isCompliantWithAllStandards]);
    audit[@"violations"] = [self getComplianceViolations];
    audit[@"recommendations"] = [self getComplianceRecommendations];
    
    return audit;
}

- (NSArray *)getComplianceViolations {
    NSMutableArray *violations = [NSMutableArray array];
    
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    // NSInteger maxAge = self.configManager.maxKeyAge; // Reserved for future use
    
    for (NSNumber *standardNum in self.enabledStandards) {
        ComplianceStandard standard = [standardNum integerValue];
        NSInteger requiredMaxAge = [self getMaxAgeForStandard:standard];
        
        if (keyAge > requiredMaxAge) {
            [violations addObject:@{
                @"type": @"KeyAgeViolation",
                @"standard": [ComplianceReporter stringForStandard:standard],
                @"currentAge": @(keyAge),
                @"maxAllowed": @(requiredMaxAge),
                @"severity": @"High"
            }];
        }
    }
    
    if (![self.lifecycleTracker isCurrentKeyEscrowed]) {
        [violations addObject:@{
            @"type": @"EscrowViolation",
            @"description": @"Current key is not escrowed",
            @"severity": @"Critical"
        }];
    }
    
    KeyMetadata *currentKey = [self.lifecycleTracker getCurrentKey];
    if (currentKey && !currentKey.escrowVerified) {
        [violations addObject:@{
            @"type": @"VerificationViolation",
            @"description": @"Key escrow not verified",
            @"severity": @"Medium"
        }];
    }
    
    return violations;
}

- (BOOL)isCompliantWithAllStandards {
    for (NSNumber *standardNum in self.enabledStandards) {
        ComplianceStandard standard = [standardNum integerValue];
        if ([self checkComplianceForStandard:standard] != ComplianceStatusCompliant) {
            return NO;
        }
    }
    return YES;
}

#pragma mark - Report Generation

- (ComplianceReport *)generateComplianceReport {
    return [self generateReportForStandard:self.primaryStandard];
}

- (ComplianceReport *)generateReportForStandard:(ComplianceStandard)standard {
    ComplianceReport *report = [[ComplianceReport alloc] init];
    report.standard = standard;
    report.status = [self checkComplianceForStandard:standard];
    
    NSMutableDictionary *findings = [NSMutableDictionary dictionary];
    
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    findings[@"currentKeyAge"] = @(keyAge);
    findings[@"keyCreationDate"] = [self.lifecycleTracker getCurrentKeyCreationDate] ?: [NSNull null];
    findings[@"isEscrowed"] = @([self.lifecycleTracker isCurrentKeyEscrowed]);
    findings[@"rotationCount"] = @([self.lifecycleTracker getTotalRotationCount]);
    findings[@"averageKeyLifetime"] = @([self.lifecycleTracker getAverageKeyLifetime]);
    
    report.findings = findings;
    report.violations = [self getComplianceViolations];
    report.recommendations = [self getRecommendationsForStandard:standard];
    report.metrics = [self getMetricsForStandard:standard];
    
    [self.reportHistory addObject:report];
    
    [self.logger logComplianceEvent:@"Report Generated" 
                           standard:[ComplianceReporter stringForStandard:standard] 
                             status:(report.status == ComplianceStatusCompliant)];
    
    return report;
}

- (NSString *)generateReportInFormat:(ReportFormat)format {
    ComplianceReport *report = [self generateComplianceReport];
    
    switch (format) {
        case ReportFormatJSON:
            return [self generateJSONReport:report];
        case ReportFormatXML:
            return [self generateXMLReport:report];
        case ReportFormatCSV:
            return [self generateCSVReport:report];
        case ReportFormatHTML:
            return [self generateHTMLReport:report];
        default:
            return [self generateJSONReport:report];
    }
}

- (NSData *)generateReportData:(ReportFormat)format {
    NSString *reportString = [self generateReportInFormat:format];
    return [reportString dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Standard-Specific Checks

- (ComplianceStatus)checkNISTCompliance {
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    BOOL isEscrowed = [self.lifecycleTracker isCurrentKeyEscrowed];
    
    if (!isEscrowed) {
        return ComplianceStatusNonCompliant;
    }
    
    if (keyAge > 90) {
        return ComplianceStatusNonCompliant;
    } else if (keyAge > 75) {
        return ComplianceStatusWarning;
    }
    
    return ComplianceStatusCompliant;
}

- (ComplianceStatus)checkISO27001Compliance {
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    BOOL isEscrowed = [self.lifecycleTracker isCurrentKeyEscrowed];
    
    if (!isEscrowed) {
        return ComplianceStatusNonCompliant;
    }
    
    if (keyAge > 180) {
        return ComplianceStatusNonCompliant;
    } else if (keyAge > 150) {
        return ComplianceStatusWarning;
    }
    
    NSDictionary *stats = [self.lifecycleTracker getKeyStatistics];
    NSInteger avgLifetime = [stats[@"averageLifetime"] integerValue];
    
    if (avgLifetime > 180) {
        return ComplianceStatusWarning;
    }
    
    return ComplianceStatusCompliant;
}

- (ComplianceStatus)checkPCIDSSCompliance {
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    BOOL isEscrowed = [self.lifecycleTracker isCurrentKeyEscrowed];
    KeyMetadata *currentKey = [self.lifecycleTracker getCurrentKey];
    
    if (!isEscrowed || !currentKey.escrowVerified) {
        return ComplianceStatusNonCompliant;
    }
    
    if (keyAge > 90) {
        return ComplianceStatusNonCompliant;
    } else if (keyAge > 75) {
        return ComplianceStatusWarning;
    }
    
    if (self.configManager.enforceKeyComplexity == NO) {
        return ComplianceStatusWarning;
    }
    
    return ComplianceStatusCompliant;
}

- (ComplianceStatus)checkHIPAACompliance {
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    BOOL isEscrowed = [self.lifecycleTracker isCurrentKeyEscrowed];
    KeyMetadata *currentKey = [self.lifecycleTracker getCurrentKey];
    
    if (!isEscrowed || !currentKey.escrowVerified) {
        return ComplianceStatusNonCompliant;
    }
    
    if (keyAge > 90) {
        return ComplianceStatusNonCompliant;
    } else if (keyAge > 60) {
        return ComplianceStatusWarning;
    }
    
    NSArray *auditTrail = [[EnhancedLogger sharedLogger] getAuditTrail:30];
    if (auditTrail.count == 0) {
        return ComplianceStatusWarning;
    }
    
    return ComplianceStatusCompliant;
}

- (ComplianceStatus)checkSOC2Compliance {
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    BOOL isEscrowed = [self.lifecycleTracker isCurrentKeyEscrowed];
    
    if (!isEscrowed) {
        return ComplianceStatusNonCompliant;
    }
    
    if (keyAge > 365) {
        return ComplianceStatusNonCompliant;
    } else if (keyAge > 300) {
        return ComplianceStatusWarning;
    }
    
    NSDictionary *complianceReport = [self.lifecycleTracker generateComplianceReport];
    BOOL hasViolations = [complianceReport[@"violations"] count] > 0;
    
    if (hasViolations) {
        return ComplianceStatusWarning;
    }
    
    return ComplianceStatusCompliant;
}

- (ComplianceStatus)checkCustomCompliance:(NSDictionary *)requirements {
    NSInteger maxAge = [requirements[@"maxKeyAge"] integerValue] ?: 365;
    BOOL requireEscrow = [requirements[@"requireEscrow"] boolValue];
    BOOL requireVerification = [requirements[@"requireVerification"] boolValue];
    
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    BOOL isEscrowed = [self.lifecycleTracker isCurrentKeyEscrowed];
    KeyMetadata *currentKey = [self.lifecycleTracker getCurrentKey];
    
    if (requireEscrow && !isEscrowed) {
        return ComplianceStatusNonCompliant;
    }
    
    if (requireVerification && !currentKey.escrowVerified) {
        return ComplianceStatusNonCompliant;
    }
    
    if (keyAge > maxAge) {
        return ComplianceStatusNonCompliant;
    } else if (keyAge > (maxAge * 0.8)) {
        return ComplianceStatusWarning;
    }
    
    return ComplianceStatusCompliant;
}

#pragma mark - Detailed Compliance Metrics

- (NSDictionary *)getMetricsForStandard:(ComplianceStandard)standard {
    switch (standard) {
        case ComplianceStandardNIST:
            return [self getNISTMetrics];
        case ComplianceStandardISO27001:
            return [self getISO27001Metrics];
        case ComplianceStandardPCIDSS:
            return [self getPCIDSSMetrics];
        case ComplianceStandardHIPAA:
            return [self getHIPAAMetrics];
        case ComplianceStandardSOC2:
            return [self getSOC2Metrics];
        default:
            return @{};
    }
}

- (NSDictionary *)getNISTMetrics {
    return @{
        @"standard": @"NIST 800-171",
        @"maxKeyAge": @90,
        @"currentKeyAge": @([self.lifecycleTracker getCurrentKeyAgeDays]),
        @"requiresEscrow": @YES,
        @"escrowStatus": @([self.lifecycleTracker isCurrentKeyEscrowed]),
        @"complianceScore": @([self calculateComplianceScore:90])
    };
}

- (NSDictionary *)getISO27001Metrics {
    return @{
        @"standard": @"ISO 27001:2013",
        @"maxKeyAge": @180,
        @"currentKeyAge": @([self.lifecycleTracker getCurrentKeyAgeDays]),
        @"requiresEscrow": @YES,
        @"escrowStatus": @([self.lifecycleTracker isCurrentKeyEscrowed]),
        @"complianceScore": @([self calculateComplianceScore:180]),
        @"averageKeyLifetime": @([self.lifecycleTracker getAverageKeyLifetime])
    };
}

- (NSDictionary *)getPCIDSSMetrics {
    return @{
        @"standard": @"PCI-DSS 4.0",
        @"maxKeyAge": @90,
        @"currentKeyAge": @([self.lifecycleTracker getCurrentKeyAgeDays]),
        @"requiresEscrow": @YES,
        @"requiresVerification": @YES,
        @"escrowStatus": @([self.lifecycleTracker isCurrentKeyEscrowed]),
        @"verificationStatus": @([self.lifecycleTracker getCurrentKey].escrowVerified),
        @"complianceScore": @([self calculateComplianceScore:90])
    };
}

- (NSDictionary *)getHIPAAMetrics {
    return @{
        @"standard": @"HIPAA Security Rule",
        @"maxKeyAge": @90,
        @"currentKeyAge": @([self.lifecycleTracker getCurrentKeyAgeDays]),
        @"requiresEscrow": @YES,
        @"requiresAuditLog": @YES,
        @"escrowStatus": @([self.lifecycleTracker isCurrentKeyEscrowed]),
        @"auditLogEnabled": @(self.logger.enableFileLogging),
        @"complianceScore": @([self calculateComplianceScore:90])
    };
}

- (NSDictionary *)getSOC2Metrics {
    return @{
        @"standard": @"SOC 2 Type II",
        @"maxKeyAge": @365,
        @"currentKeyAge": @([self.lifecycleTracker getCurrentKeyAgeDays]),
        @"requiresEscrow": @YES,
        @"escrowStatus": @([self.lifecycleTracker isCurrentKeyEscrowed]),
        @"complianceScore": @([self calculateComplianceScore:365]),
        @"controlsImplemented": @([self getImplementedControlsCount]),
        @"totalControls": @15
    };
}

#pragma mark - Export and Storage

- (BOOL)exportReportToFile:(ComplianceReport *)report path:(NSString *)path format:(ReportFormat)format {
    NSString *reportContent;
    
    switch (format) {
        case ReportFormatJSON:
            reportContent = [self generateJSONReport:report];
            break;
        case ReportFormatXML:
            reportContent = [self generateXMLReport:report];
            break;
        case ReportFormatCSV:
            reportContent = [self generateCSVReport:report];
            break;
        case ReportFormatHTML:
            reportContent = [self generateHTMLReport:report];
            break;
        default:
            reportContent = [self generateJSONReport:report];
            break;
    }
    
    NSError *error;
    BOOL success = [reportContent writeToFile:path 
                                    atomically:YES 
                                      encoding:NSUTF8StringEncoding 
                                         error:&error];
    
    if (!success) {
        [self.logger error:@"Failed to export compliance report" withError:error];
    }
    
    return success;
}

- (BOOL)archiveReport:(ComplianceReport *)report {
    NSString *fileName = [NSString stringWithFormat:@"report_%@.json", report.reportID];
    NSString *filePath = [self.reportStoragePath stringByAppendingPathComponent:fileName];
    
    return [self exportReportToFile:report path:filePath format:ReportFormatJSON];
}

- (NSArray<ComplianceReport *> *)getArchivedReports:(NSInteger)count {
    // Implementation would read archived reports from storage
    return [self.reportHistory subarrayWithRange:NSMakeRange(MAX(0, self.reportHistory.count - count), 
                                                             MIN(count, self.reportHistory.count))];
}

- (ComplianceReport *)getReportByID:(NSString *)reportID {
    for (ComplianceReport *report in self.reportHistory) {
        if ([report.reportID isEqualToString:reportID]) {
            return report;
        }
    }
    return nil;
}

#pragma mark - Scheduling and Automation

- (void)scheduleAutomaticReporting {
    if (self.scheduledReportTimer) {
        [self.scheduledReportTimer invalidate];
    }
    
    NSTimeInterval interval = self.reportingIntervalDays * 86400;
    
    self.scheduledReportTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                                 target:self
                                                               selector:@selector(generateAndSubmitScheduledReport)
                                                               userInfo:nil
                                                                repeats:YES];
    
    [self.logger info:@"Scheduled automatic compliance reporting"];
}

- (void)cancelScheduledReporting {
    if (self.scheduledReportTimer) {
        [self.scheduledReportTimer invalidate];
        self.scheduledReportTimer = nil;
        [self.logger info:@"Cancelled scheduled compliance reporting"];
    }
}

- (NSDate *)getNextScheduledReportDate {
    if (!self.scheduledReportTimer) {
        return nil;
    }
    
    return [self.scheduledReportTimer fireDate];
}

- (void)generateAndSubmitScheduledReport {
    ComplianceReport *report = [self generateComplianceReport];
    
    [self archiveReport:report];
    
    if (self.configManager.enableAPIIntegration) {
        [self submitReportToJamf:report completion:^(BOOL success, NSError *error) {
            if (success) {
                [self.logger info:@"Successfully submitted scheduled compliance report to Jamf"];
            } else {
                [self.logger error:@"Failed to submit scheduled compliance report" withError:error];
            }
        }];
    }
    
    if (self.configManager.enableWebhooks && self.configManager.webhookURL) {
        [self submitReportToWebhook:report 
                         webhookURL:self.configManager.webhookURL 
                         completion:^(BOOL success, NSError *error) {
            if (success) {
                [self.logger info:@"Successfully submitted scheduled compliance report to webhook"];
            } else {
                [self.logger error:@"Failed to submit report to webhook" withError:error];
            }
        }];
    }
}

#pragma mark - Integration

- (void)submitReportToJamf:(ComplianceReport *)report 
                completion:(void(^)(BOOL success, NSError *error))completion {
    
    // Write report to Extension Attribute file for Jamf to pick up
    NSDictionary *reportData = [report toDictionary];
    NSString *eaPath = @"/Library/Application Support/JAMF/compliance_report.plist";
    
    // Create directory if needed
    NSString *directory = [eaPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:nil];
    
    NSError *writeError;
    BOOL success = [reportData writeToFile:eaPath atomically:YES];
    
    if (completion) {
        if (success) {
            // Optionally trigger recon to update immediately
            NSTask *reconTask = [[NSTask alloc] init];
            reconTask.launchPath = @"/usr/local/bin/jamf";
            reconTask.arguments = @[@"recon"];
            @try {
                [reconTask launch];
            }
            @catch (NSException *exception) {
                // Ignore recon errors
            }
            completion(YES, nil);
        } else {
            completion(NO, writeError);
        }
    }
}

- (void)submitReportToWebhook:(ComplianceReport *)report 
                   webhookURL:(NSString *)url 
                   completion:(void(^)(BOOL success, NSError *error))completion {
    
    NSDictionary *reportData = [report toDictionary];
    
    // Create webhook request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:reportData options:0 error:&jsonError];
    
    if (jsonError) {
        if (completion) completion(NO, jsonError);
        return;
    }
    
    request.HTTPBody = jsonData;
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(error == nil, error);
            });
        }
    }];
    
    [task resume];
}

- (void)emailReport:(ComplianceReport *)report 
         recipients:(NSArray<NSString *> *)recipients 
         completion:(void(^)(BOOL success, NSError *error))completion {
    
    // Check if SMTP is enabled
    if (self.configManager.enableSMTP && self.configManager.smtpServer) {
        // Use SMTP relay
        [self sendReportViaSMTP:report recipients:recipients completion:completion];
    } else {
        // Fallback to Mail.app via AppleScript
        [self sendReportViaMailApp:report recipients:recipients completion:completion];
    }
}

- (void)sendReportViaSMTP:(ComplianceReport *)report
               recipients:(NSArray<NSString *> *)recipients
               completion:(void(^)(BOOL success, NSError *error))completion {
    
    NSString *subject = [NSString stringWithFormat:@"Escrow Buddy Enhanced Compliance Report - %@",
                        [report statusString]];
    NSString *body = [self generateEmailBody:report];
    
    // Build email message in MIME format
    NSMutableString *message = [NSMutableString string];
    
    // Email headers
    [message appendFormat:@"From: %@ <%@>\r\n",
     self.configManager.smtpFromName ?: @"Escrow Buddy Enhanced",
     self.configManager.smtpFromAddress ?: @"escrow-buddy@company.com"];
    
    [message appendFormat:@"To: %@\r\n", [recipients componentsJoinedByString:@", "]];
    [message appendFormat:@"Subject: %@\r\n", subject];
    [message appendString:@"MIME-Version: 1.0\r\n"];
    [message appendString:@"Content-Type: text/plain; charset=UTF-8\r\n"];
    [message appendString:@"Content-Transfer-Encoding: 8bit\r\n"];
    [message appendString:@"\r\n"];
    [message appendString:body];
    
    // Create SMTP connection and send
    [self sendSMTPMessage:message
                  toServer:self.configManager.smtpServer
                      port:self.configManager.smtpPort
                  useSSL:self.configManager.smtpUseSSL
             useSTARTTLS:self.configManager.smtpUseSTARTTLS
                 username:self.configManager.smtpUsername
                 password:self.configManager.smtpPassword
               completion:^(BOOL success, NSError *error) {
        if (success) {
            [self.logger info:@"Successfully sent compliance report via SMTP to %lu recipients",
             (unsigned long)recipients.count];
        } else {
            [self.logger error:@"Failed to send compliance report via SMTP" withError:error];
        }
        if (completion) completion(success, error);
    }];
}

- (void)sendSMTPMessage:(NSString *)message
               toServer:(NSString *)server
                   port:(NSInteger)port
                 useSSL:(BOOL)useSSL
            useSTARTTLS:(BOOL)useSTARTTLS
               username:(NSString *)username
               password:(NSString *)password
             completion:(void(^)(BOOL success, NSError *error))completion {
    
    // Build SMTP URL
    NSString *protocol = useSSL ? @"smtps" : @"smtp";
    NSString *urlString = [NSString stringWithFormat:@"%@://%@:%ld", protocol, server, (long)port];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"SMTPError"
                                             code:400
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid SMTP server URL"}];
        if (completion) completion(NO, error);
        return;
    }
    
    // For a proper SMTP implementation, we would need to:
    // 1. Establish TCP connection
    // 2. Handle SMTP protocol (EHLO, AUTH, MAIL FROM, RCPT TO, DATA)
    // 3. Handle TLS/SSL encryption
    // 4. Send the message
    
    // Since implementing full SMTP protocol is complex, we'll use a simplified approach
    // that sends the email data to an SMTP relay endpoint that handles the protocol
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    // Add authentication if required
    if (self.configManager.smtpRequiresAuth && username && password) {
        NSString *authString = [NSString stringWithFormat:@"%@:%@", username, password];
        NSData *authData = [authString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *authValue = [NSString stringWithFormat:@"Basic %@",
                              [authData base64EncodedStringWithOptions:0]];
        [request setValue:authValue forHTTPHeaderField:@"Authorization"];
    }
    
    // Set message body
    request.HTTPBody = [message dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"message/rfc822" forHTTPHeaderField:@"Content-Type"];
    
    // Create session with proper configuration
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 30.0;
    
    if (useSSL || useSTARTTLS) {
        // Configure TLS
        config.TLSMinimumSupportedProtocol = kTLSProtocol12;
    }
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, error);
                });
            }
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        BOOL success = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300);
        
        if (!success) {
            NSError *smtpError = [NSError errorWithDomain:@"SMTPError"
                                                     code:httpResponse.statusCode
                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                          [NSString stringWithFormat:@"SMTP server returned status %ld",
                                                           (long)httpResponse.statusCode]}];
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, smtpError);
                });
            }
        } else {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(YES, nil);
                });
            }
        }
    }];
    
    [task resume];
}

- (void)sendReportViaMailApp:(ComplianceReport *)report
                   recipients:(NSArray<NSString *> *)recipients
                   completion:(void(^)(BOOL success, NSError *error))completion {
    
    NSString *subject = [NSString stringWithFormat:@"Escrow Buddy Enhanced Compliance Report - %@",
                        [report statusString]];
    
    NSString *body = [self generateEmailBody:report];
    NSString *recipientList = [recipients componentsJoinedByString:@", "];
    
    // Create AppleScript to send email
    NSString *script = [NSString stringWithFormat:
        @"tell application \"Mail\"\n"
        @"  set newMessage to make new outgoing message with properties {subject:\"%@\", content:\"%@\", visible:false}\n"
        @"  tell newMessage\n"
        @"    make new to recipient at end of to recipients with properties {address:\"%@\"}\n"
        @"  end tell\n"
        @"  send newMessage\n"
        @"end tell",
        [subject stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""],
        [body stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""],
        recipientList];
    
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary *errorDict = nil;
    NSAppleEventDescriptor *result = [appleScript executeAndReturnError:&errorDict];
    
    if (errorDict) {
        NSError *error = [NSError errorWithDomain:@"ComplianceReporter"
                                             code:502
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to send email via Mail.app",
                                                   NSUnderlyingErrorKey: errorDict}];
        if (completion) completion(NO, error);
    } else {
        [self.logger info:@"Successfully sent compliance report email via Mail.app to %lu recipients",
         (unsigned long)recipients.count];
        if (completion) completion(YES, nil);
    }
}

- (NSString *)generateEmailBody:(ComplianceReport *)report {
    NSMutableString *body = [NSMutableString string];
    
    [body appendString:@"Escrow Buddy Enhanced Compliance Report\n"];
    [body appendString:@"========================================\n\n"];
    
    [body appendFormat:@"Report Date: %@\n", report.generatedDate];
    [body appendFormat:@"Compliance Standard: %@\n", report.standard];
    [body appendFormat:@"Status: %@\n\n", [report statusString]];
    
    [body appendFormat:@"Total Devices: %lu\n", (unsigned long)report.totalDevices];
    [body appendFormat:@"Compliant Devices: %lu\n", (unsigned long)report.compliantDevices];
    [body appendFormat:@"Non-Compliant Devices: %lu\n", (unsigned long)report.nonCompliantDevices];
    [body appendFormat:@"Compliance Rate: %.1f%%\n\n", report.compliancePercentage];
    
    if (report.violations.count > 0) {
        [body appendString:@"Violations:\n"];
        for (NSString *violation in report.violations) {
            [body appendFormat:@"- %@\n", violation];
        }
    }
    
    if (report.recommendations.count > 0) {
        [body appendString:@"\nRecommendations:\n"];
        for (NSString *recommendation in report.recommendations) {
            [body appendFormat:@"- %@\n", recommendation];
        }
    }
    
    [body appendString:@"\n---\n"];
    [body appendString:@"Generated by Escrow Buddy Enhanced\n"];
    
    return body;
}

#pragma mark - Compliance History

- (NSArray *)getComplianceHistory:(NSInteger)days {
    NSDate *cutoffDate = [[NSDate date] dateByAddingTimeInterval:-days * 86400];
    NSMutableArray *history = [NSMutableArray array];
    
    for (ComplianceReport *report in self.reportHistory) {
        if ([report.generatedDate compare:cutoffDate] == NSOrderedDescending) {
            [history addObject:[report toDictionary]];
        }
    }
    
    return history;
}

- (NSDictionary *)getComplianceTrends {
    NSMutableDictionary *trends = [NSMutableDictionary dictionary];
    
    NSInteger compliantCount = 0;
    NSInteger nonCompliantCount = 0;
    NSInteger warningCount = 0;
    
    for (ComplianceReport *report in self.reportHistory) {
        switch (report.status) {
            case ComplianceStatusCompliant:
                compliantCount++;
                break;
            case ComplianceStatusNonCompliant:
                nonCompliantCount++;
                break;
            case ComplianceStatusWarning:
                warningCount++;
                break;
            default:
                break;
        }
    }
    
    trends[@"totalReports"] = @(self.reportHistory.count);
    trends[@"compliantReports"] = @(compliantCount);
    trends[@"nonCompliantReports"] = @(nonCompliantCount);
    trends[@"warningReports"] = @(warningCount);
    trends[@"complianceRate"] = @(self.reportHistory.count > 0 ? 
                                  (CGFloat)compliantCount / self.reportHistory.count : 0);
    
    return trends;
}

- (CGFloat)getComplianceScore {
    ComplianceStatus status = [self checkCompliance];
    
    switch (status) {
        case ComplianceStatusCompliant:
            return 100.0;
        case ComplianceStatusWarning:
            return 75.0;
        case ComplianceStatusNonCompliant:
            return 25.0;
        default:
            return 0.0;
    }
}

- (CGFloat)getHistoricalComplianceScore:(NSInteger)daysAgo {
    // Implementation would calculate score from historical data
    return [self getComplianceScore];
}

#pragma mark - Violation Management

- (void)recordViolation:(NSString *)violationType 
             description:(NSString *)description 
                severity:(NSString *)severity {
    
    NSMutableDictionary *violation = [NSMutableDictionary dictionary];
    violation[@"type"] = violationType;
    violation[@"description"] = description;
    violation[@"severity"] = severity;
    violation[@"timestamp"] = [NSDate date];
    violation[@"resolved"] = @NO;
    
    [self.violationHistory addObject:violation];
    [self saveViolationHistory];
    
    [self.logger logSecurityEvent:violationType 
                          severity:severity 
                           details:violation];
}

- (NSArray *)getViolationHistory:(NSInteger)days {
    NSDate *cutoffDate = [[NSDate date] dateByAddingTimeInterval:-days * 86400];
    NSMutableArray *recentViolations = [NSMutableArray array];
    
    for (NSDictionary *violation in self.violationHistory) {
        NSDate *timestamp = violation[@"timestamp"];
        if ([timestamp compare:cutoffDate] == NSOrderedDescending) {
            [recentViolations addObject:violation];
        }
    }
    
    return recentViolations;
}

- (BOOL)hasActiveViolations {
    for (NSDictionary *violation in self.violationHistory) {
        if (![violation[@"resolved"] boolValue]) {
            return YES;
        }
    }
    return NO;
}

- (NSInteger)getViolationCount:(NSInteger)days {
    return [[self getViolationHistory:days] count];
}

#pragma mark - Recommendations

- (NSArray *)getComplianceRecommendations {
    return [self getRecommendationsForStandard:self.primaryStandard];
}

- (NSArray *)getRecommendationsForStandard:(ComplianceStandard)standard {
    NSMutableArray *recommendations = [NSMutableArray array];
    
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    NSInteger maxAge = [self getMaxAgeForStandard:standard];
    
    if (keyAge > maxAge * 0.8) {
        [recommendations addObject:@{
            @"priority": @"High",
            @"recommendation": @"Schedule key rotation soon",
            @"reason": [NSString stringWithFormat:@"Key age (%ld days) approaching maximum (%ld days)", 
                       (long)keyAge, (long)maxAge]
        }];
    }
    
    if (![self.lifecycleTracker isCurrentKeyEscrowed]) {
        [recommendations addObject:@{
            @"priority": @"Critical",
            @"recommendation": @"Ensure key is properly escrowed",
            @"reason": @"Key escrow is required for compliance"
        }];
    }
    
    KeyMetadata *currentKey = [self.lifecycleTracker getCurrentKey];
    if (currentKey && !currentKey.escrowVerified) {
        [recommendations addObject:@{
            @"priority": @"Medium",
            @"recommendation": @"Verify key escrow with MDM",
            @"reason": @"Escrow verification ensures recovery capability"
        }];
    }
    
    if (!self.configManager.autoRotationEnabled) {
        [recommendations addObject:@{
            @"priority": @"Medium",
            @"recommendation": @"Enable automatic key rotation",
            @"reason": @"Automation reduces compliance risks"
        }];
    }
    
    return recommendations;
}

- (NSDictionary *)getPriorityRecommendations {
    NSArray *allRecommendations = [self getComplianceRecommendations];
    
    NSMutableArray *critical = [NSMutableArray array];
    NSMutableArray *high = [NSMutableArray array];
    NSMutableArray *medium = [NSMutableArray array];
    NSMutableArray *low = [NSMutableArray array];
    
    for (NSDictionary *rec in allRecommendations) {
        NSString *priority = rec[@"priority"];
        if ([priority isEqualToString:@"Critical"]) {
            [critical addObject:rec];
        } else if ([priority isEqualToString:@"High"]) {
            [high addObject:rec];
        } else if ([priority isEqualToString:@"Medium"]) {
            [medium addObject:rec];
        } else {
            [low addObject:rec];
        }
    }
    
    return @{
        @"critical": critical,
        @"high": high,
        @"medium": medium,
        @"low": low
    };
}

#pragma mark - Helper Methods

- (NSInteger)getMaxAgeForStandard:(ComplianceStandard)standard {
    switch (standard) {
        case ComplianceStandardNIST:
        case ComplianceStandardPCIDSS:
        case ComplianceStandardHIPAA:
            return 90;
        case ComplianceStandardISO27001:
            return 180;
        case ComplianceStandardSOC2:
            return 365;
        default:
            return 365;
    }
}

- (CGFloat)calculateComplianceScore:(NSInteger)maxAge {
    NSInteger keyAge = [self.lifecycleTracker getCurrentKeyAgeDays];
    BOOL isEscrowed = [self.lifecycleTracker isCurrentKeyEscrowed];
    
    if (!isEscrowed) {
        return 0.0;
    }
    
    if (keyAge > maxAge) {
        return 0.0;
    }
    
    CGFloat ageScore = 100.0 * (1.0 - (CGFloat)keyAge / maxAge);
    return ageScore;
}

- (NSInteger)getImplementedControlsCount {
    NSInteger count = 0;
    
    if ([self.lifecycleTracker isCurrentKeyEscrowed]) count++;
    if (self.configManager.autoRotationEnabled) count++;
    if (self.configManager.enableComplianceReporting) count++;
    if (self.logger.enableFileLogging) count++;
    if (self.configManager.enforceKeyComplexity) count++;
    
    return count;
}

#pragma mark - Report Formatting

- (NSString *)generateJSONReport:(ComplianceReport *)report {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[report toDictionary]
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:&error];
    
    if (error) {
        [self.logger error:@"Failed to generate JSON report" withError:error];
        return @"{}";
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)generateXMLReport:(ComplianceReport *)report {
    NSMutableString *xml = [NSMutableString string];
    
    [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [xml appendString:@"<ComplianceReport>\n"];
    [xml appendFormat:@"  <ReportID>%@</ReportID>\n", report.reportID];
    [xml appendFormat:@"  <GeneratedDate>%@</GeneratedDate>\n", 
     [self.dateFormatter stringFromDate:report.generatedDate]];
    [xml appendFormat:@"  <Standard>%@</Standard>\n", 
     [ComplianceReporter stringForStandard:report.standard]];
    [xml appendFormat:@"  <Status>%@</Status>\n", 
     [ComplianceReporter stringForStatus:report.status]];
    
    [xml appendString:@"  <Findings>\n"];
    for (NSString *key in report.findings) {
        [xml appendFormat:@"    <%@>%@</%@>\n", key, report.findings[key], key];
    }
    [xml appendString:@"  </Findings>\n"];
    
    [xml appendString:@"</ComplianceReport>"];
    
    return xml;
}

- (NSString *)generateCSVReport:(ComplianceReport *)report {
    NSMutableString *csv = [NSMutableString string];
    
    [csv appendString:@"Field,Value\n"];
    [csv appendFormat:@"Report ID,%@\n", report.reportID];
    [csv appendFormat:@"Generated Date,%@\n", [self.dateFormatter stringFromDate:report.generatedDate]];
    [csv appendFormat:@"Standard,%@\n", [ComplianceReporter stringForStandard:report.standard]];
    [csv appendFormat:@"Status,%@\n", [ComplianceReporter stringForStatus:report.status]];
    [csv appendFormat:@"Violations,%lu\n", (unsigned long)report.violations.count];
    [csv appendFormat:@"Recommendations,%lu\n", (unsigned long)report.recommendations.count];
    
    for (NSString *key in report.findings) {
        [csv appendFormat:@"%@,%@\n", key, report.findings[key]];
    }
    
    return csv;
}

- (NSString *)generateHTMLReport:(ComplianceReport *)report {
    NSMutableString *html = [NSMutableString string];
    
    [html appendString:@"<!DOCTYPE html>\n<html>\n<head>\n"];
    [html appendString:@"<title>Compliance Report</title>\n"];
    [html appendString:@"<style>body{font-family:Arial,sans-serif;margin:20px;}"];
    [html appendString:@"table{border-collapse:collapse;width:100%;}"];
    [html appendString:@"th,td{border:1px solid #ddd;padding:8px;text-align:left;}"];
    [html appendString:@"th{background-color:#f2f2f2;}</style>\n"];
    [html appendString:@"</head>\n<body>\n"];
    
    [html appendFormat:@"<h1>Compliance Report</h1>\n"];
    [html appendFormat:@"<p><strong>Report ID:</strong> %@</p>\n", report.reportID];
    [html appendFormat:@"<p><strong>Generated:</strong> %@</p>\n", 
     [self.dateFormatter stringFromDate:report.generatedDate]];
    [html appendFormat:@"<p><strong>Standard:</strong> %@</p>\n", 
     [ComplianceReporter stringForStandard:report.standard]];
    [html appendFormat:@"<p><strong>Status:</strong> %@</p>\n", 
     [ComplianceReporter stringForStatus:report.status]];
    
    [html appendString:@"<h2>Findings</h2>\n<table>\n"];
    for (NSString *key in report.findings) {
        [html appendFormat:@"<tr><td>%@</td><td>%@</td></tr>\n", key, report.findings[key]];
    }
    [html appendString:@"</table>\n"];
    
    if (report.violations.count > 0) {
        [html appendString:@"<h2>Violations</h2>\n<ul>\n"];
        for (NSDictionary *violation in report.violations) {
            [html appendFormat:@"<li>%@ - %@</li>\n", 
             violation[@"type"], violation[@"description"]];
        }
        [html appendString:@"</ul>\n"];
    }
    
    [html appendString:@"</body>\n</html>"];
    
    return html;
}

#pragma mark - Utility Methods

+ (NSString *)stringForStandard:(ComplianceStandard)standard {
    switch (standard) {
        case ComplianceStandardNIST: return @"NIST";
        case ComplianceStandardISO27001: return @"ISO27001";
        case ComplianceStandardPCIDSS: return @"PCI-DSS";
        case ComplianceStandardHIPAA: return @"HIPAA";
        case ComplianceStandardSOC2: return @"SOC2";
        case ComplianceStandardCustom: return @"Custom";
        default: return @"None";
    }
}

+ (NSString *)stringForStatus:(ComplianceStatus)status {
    switch (status) {
        case ComplianceStatusCompliant: return @"Compliant";
        case ComplianceStatusNonCompliant: return @"Non-Compliant";
        case ComplianceStatusWarning: return @"Warning";
        default: return @"Unknown";
    }
}

+ (NSString *)stringForFormat:(ReportFormat)format {
    switch (format) {
        case ReportFormatJSON: return @"JSON";
        case ReportFormatXML: return @"XML";
        case ReportFormatCSV: return @"CSV";
        case ReportFormatHTML: return @"HTML";
        case ReportFormatPDF: return @"PDF";
        default: return @"Unknown";
    }
}

+ (ComplianceStandard)standardFromString:(NSString *)string {
    if ([string isEqualToString:@"NIST"]) return ComplianceStandardNIST;
    if ([string isEqualToString:@"ISO27001"]) return ComplianceStandardISO27001;
    if ([string isEqualToString:@"PCI-DSS"]) return ComplianceStandardPCIDSS;
    if ([string isEqualToString:@"HIPAA"]) return ComplianceStandardHIPAA;
    if ([string isEqualToString:@"SOC2"]) return ComplianceStandardSOC2;
    if ([string isEqualToString:@"Custom"]) return ComplianceStandardCustom;
    return ComplianceStandardNone;
}

@end