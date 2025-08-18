//
//  ComplianceReporter.h
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

typedef NS_ENUM(NSInteger, ComplianceStandard) {
    ComplianceStandardNone = 0,
    ComplianceStandardNIST,
    ComplianceStandardISO27001,
    ComplianceStandardPCIDSS,
    ComplianceStandardHIPAA,
    ComplianceStandardSOC2,
    ComplianceStandardCustom
};

typedef NS_ENUM(NSInteger, ComplianceStatus) {
    ComplianceStatusCompliant = 0,
    ComplianceStatusNonCompliant,
    ComplianceStatusWarning,
    ComplianceStatusUnknown
};

typedef NS_ENUM(NSInteger, ReportFormat) {
    ReportFormatJSON = 0,
    ReportFormatXML,
    ReportFormatCSV,
    ReportFormatHTML,
    ReportFormatPDF
};

@interface ComplianceReport : NSObject
@property (nonatomic, strong) NSDate *generatedDate;
@property (nonatomic, assign) ComplianceStandard standard;
@property (nonatomic, assign) ComplianceStatus status;
@property (nonatomic, strong) NSString *reportID;
@property (nonatomic, strong) NSDictionary *findings;
@property (nonatomic, strong) NSArray *violations;
@property (nonatomic, strong) NSArray *recommendations;
@property (nonatomic, strong) NSDictionary *metrics;
@end

@interface ComplianceReporter : NSObject

#pragma mark - Singleton

+ (instancetype)sharedReporter;

#pragma mark - Configuration

@property (nonatomic, assign) ComplianceStandard primaryStandard;
@property (nonatomic, strong) NSArray<NSNumber *> *enabledStandards;
@property (nonatomic, assign) BOOL autoReporting;
@property (nonatomic, assign) NSInteger reportingIntervalDays;
@property (nonatomic, strong) NSString * _Nullable reportStoragePath;

#pragma mark - Compliance Checking

- (ComplianceStatus)checkCompliance;
- (ComplianceStatus)checkComplianceForStandard:(ComplianceStandard)standard;
- (NSDictionary *)performComplianceAudit;
- (NSArray *)getComplianceViolations;
- (BOOL)isCompliantWithAllStandards;

#pragma mark - Report Generation

- (ComplianceReport *)generateComplianceReport;
- (ComplianceReport *)generateReportForStandard:(ComplianceStandard)standard;
- (NSString *)generateReportInFormat:(ReportFormat)format;
- (NSData *)generateReportData:(ReportFormat)format;

#pragma mark - Standard-Specific Checks

- (ComplianceStatus)checkNISTCompliance;
- (ComplianceStatus)checkISO27001Compliance;
- (ComplianceStatus)checkPCIDSSCompliance;
- (ComplianceStatus)checkHIPAACompliance;
- (ComplianceStatus)checkSOC2Compliance;
- (ComplianceStatus)checkCustomCompliance:(NSDictionary *)requirements;

#pragma mark - Detailed Compliance Metrics

- (NSDictionary *)getNISTMetrics;
- (NSDictionary *)getISO27001Metrics;
- (NSDictionary *)getPCIDSSMetrics;
- (NSDictionary *)getHIPAAMetrics;
- (NSDictionary *)getSOC2Metrics;

#pragma mark - Export and Storage

- (BOOL)exportReportToFile:(ComplianceReport *)report 
                      path:(NSString *)path 
                    format:(ReportFormat)format;
- (BOOL)archiveReport:(ComplianceReport *)report;
- (NSArray<ComplianceReport *> *)getArchivedReports:(NSInteger)count;
- (ComplianceReport * _Nullable)getReportByID:(NSString *)reportID;

#pragma mark - Scheduling and Automation

- (void)scheduleAutomaticReporting;
- (void)cancelScheduledReporting;
- (NSDate * _Nullable)getNextScheduledReportDate;
- (void)generateAndSubmitScheduledReport;

#pragma mark - Integration

- (void)submitReportToJamf:(ComplianceReport *)report 
                completion:(void(^)(BOOL success, NSError * _Nullable error))completion;
- (void)submitReportToWebhook:(ComplianceReport *)report 
                   webhookURL:(NSString *)url 
                   completion:(void(^)(BOOL success, NSError * _Nullable error))completion;
- (void)emailReport:(ComplianceReport *)report 
         recipients:(NSArray<NSString *> *)recipients 
         completion:(void(^)(BOOL success, NSError * _Nullable error))completion;

#pragma mark - Compliance History

- (NSArray *)getComplianceHistory:(NSInteger)days;
- (NSDictionary *)getComplianceTrends;
- (CGFloat)getComplianceScore;
- (CGFloat)getHistoricalComplianceScore:(NSInteger)daysAgo;

#pragma mark - Violation Management

- (void)recordViolation:(NSString *)violationType 
             description:(NSString *)description 
                severity:(NSString *)severity;
- (NSArray *)getViolationHistory:(NSInteger)days;
- (BOOL)hasActiveViolations;
- (NSInteger)getViolationCount:(NSInteger)days;

#pragma mark - Recommendations

- (NSArray *)getComplianceRecommendations;
- (NSArray *)getRecommendationsForStandard:(ComplianceStandard)standard;
- (NSDictionary *)getPriorityRecommendations;

#pragma mark - Utility Methods

+ (NSString *)stringForStandard:(ComplianceStandard)standard;
+ (NSString *)stringForStatus:(ComplianceStatus)status;
+ (NSString *)stringForFormat:(ReportFormat)format;
+ (ComplianceStandard)standardFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END