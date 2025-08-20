//
//  ConfigurationManager.m
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

#import "ConfigurationManager.h"
#import <os/log.h>

static NSString *const kConfigurationDomain = @"com.netflix.Escrow-Buddy";
static NSString *const kConfigurationPlistPath = @"/Library/Preferences/com.netflix.Escrow-Buddy.plist";

@interface ConfigurationManager ()
@property (nonatomic, strong) NSMutableDictionary *configuration;
@property (nonatomic, strong) NSDictionary *defaultConfiguration;
@property (nonatomic, assign) ConfigurationSource configSource;
@property (nonatomic, strong) os_log_t logger;
@end

@implementation ConfigurationManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static ConfigurationManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logger = os_log_create("com.netflix.Escrow-Buddy", "ConfigurationManager");
        [self setupDefaultConfiguration];
        [self loadConfiguration];
    }
    return self;
}

#pragma mark - Default Configuration

- (void)setupDefaultConfiguration {
    self.defaultConfiguration = @{
        @"AutoRotationEnabled": @NO,
        @"RotationIntervalDays": @90,
        @"RotateAfterUse": @NO,
        @"MaxKeyAge": @365,
        @"RotationPolicy": @"standard",
        @"EnableComplianceReporting": @NO,
        @"ComplianceStandard": @"none",
        @"EnableWebhooks": @NO,
        @"WebhookURL": @"",
        @"EnableAPIIntegration": @NO,
        @"JamfServerURL": @"",
        @"EnableNotifications": @YES,
        @"NotificationDaysBefore": @7,
        @"NotifyOnRotationSuccess": @YES,
        @"NotifyOnRotationFailure": @YES,
        @"RequireUserAuthentication": @NO,
        @"AllowManualRotation": @YES,
        @"MinimumKeyAge": @1,
        @"EnforceKeyComplexity": @YES
    };
}

#pragma mark - Configuration Loading

- (void)loadConfiguration {
    os_log_info(self.logger, "Loading configuration");
    
    self.configuration = [NSMutableDictionary dictionaryWithDictionary:self.defaultConfiguration];
    
    NSDictionary *mdmConfig = [self getMDMConfiguration];
    if (mdmConfig) {
        os_log_info(self.logger, "Found MDM configuration");
        [self.configuration addEntriesFromDictionary:mdmConfig];
        self.configSource = ConfigurationSourceMDMProfile;
    } else {
        NSDictionary *plistConfig = [self getPlistConfiguration];
        if (plistConfig) {
            os_log_info(self.logger, "Found plist configuration");
            [self.configuration addEntriesFromDictionary:plistConfig];
            self.configSource = ConfigurationSourcePlist;
        } else {
            NSDictionary *prefsConfig = [self getPreferencesConfiguration];
            if (prefsConfig && prefsConfig.count > 0) {
                os_log_info(self.logger, "Found preferences configuration");
                [self.configuration addEntriesFromDictionary:prefsConfig];
                self.configSource = ConfigurationSourceCLI;
            } else {
                os_log_info(self.logger, "Using default configuration");
                self.configSource = ConfigurationSourceDefault;
            }
        }
    }
    
    [self validateAndSanitizeConfiguration];
}

- (NSDictionary *)getMDMConfiguration {
    NSMutableDictionary *mdmConfig = [NSMutableDictionary dictionary];
    
    for (NSString *key in self.defaultConfiguration.allKeys) {
        CFPropertyListRef value = CFPreferencesCopyValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)kConfigurationDomain,
                                                         kCFPreferencesAnyUser,
                                                         kCFPreferencesAnyHost);
        if (value && CFPreferencesAppValueIsForced((__bridge CFStringRef)key,
                                                   (__bridge CFStringRef)kConfigurationDomain)) {
            mdmConfig[key] = (__bridge id)value;
            CFRelease(value);
        } else if (value) {
            CFRelease(value);
        }
    }
    
    return mdmConfig.count > 0 ? mdmConfig : nil;
}

- (NSDictionary *)getPlistConfiguration {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kConfigurationPlistPath]) {
        return [NSDictionary dictionaryWithContentsOfFile:kConfigurationPlistPath];
    }
    return nil;
}

- (NSDictionary *)getPreferencesConfiguration {
    NSMutableDictionary *prefsConfig = [NSMutableDictionary dictionary];
    
    for (NSString *key in self.defaultConfiguration.allKeys) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)kConfigurationDomain);
        if (value) {
            prefsConfig[key] = (__bridge id)value;
            CFRelease(value);
        }
    }
    
    return prefsConfig;
}

- (void)validateAndSanitizeConfiguration {
    if (self.configuration[@"RotationIntervalDays"]) {
        NSInteger days = [self.configuration[@"RotationIntervalDays"] integerValue];
        if (![self isValidRotationInterval:days]) {
            self.configuration[@"RotationIntervalDays"] = @90;
            os_log_error(self.logger, "Invalid rotation interval, using default: 90 days");
        }
    }
    
    if (self.configuration[@"ComplianceStandard"]) {
        NSString *standard = self.configuration[@"ComplianceStandard"];
        if (![self isValidComplianceStandard:standard]) {
            self.configuration[@"ComplianceStandard"] = @"none";
            os_log_error(self.logger, "Invalid compliance standard, using default: none");
        }
    }
    
    if (self.configuration[@"WebhookURL"] && 
        ![self.configuration[@"WebhookURL"] isEqualToString:@""]) {
        NSString *url = self.configuration[@"WebhookURL"];
        if (![self isValidWebhookURL:url]) {
            self.configuration[@"EnableWebhooks"] = @NO;
            os_log_error(self.logger, "Invalid webhook URL, disabling webhooks");
        }
    }
    
    NSInteger minAge = [self.configuration[@"MinimumKeyAge"] integerValue];
    NSInteger maxAge = [self.configuration[@"MaxKeyAge"] integerValue];
    if (minAge >= maxAge) {
        self.configuration[@"MinimumKeyAge"] = @1;
        os_log_error(self.logger, "Minimum key age >= maximum key age, resetting minimum to 1");
    }
}

#pragma mark - Configuration Management

- (void)reloadConfiguration {
    os_log_info(self.logger, "Reloading configuration");
    [self loadConfiguration];
}

- (BOOL)validateConfiguration {
    NSArray *errors = [self validateConfigurationValues:self.configuration];
    if (errors.count > 0) {
        for (NSString *error in errors) {
            os_log_error(self.logger, "Configuration validation error: %{public}@", error);
        }
        return NO;
    }
    return YES;
}

- (NSDictionary *)getCurrentConfiguration {
    return [self.configuration copy];
}

- (ConfigurationSource)getConfigurationSource {
    return self.configSource;
}

#pragma mark - Configuration Updates

- (BOOL)updateConfiguration:(NSDictionary *)newConfig {
    if (self.configSource == ConfigurationSourceMDMProfile) {
        os_log_error(self.logger, "Cannot update MDM-managed configuration");
        return NO;
    }
    
    NSArray *errors = [self validateConfigurationValues:newConfig];
    if (errors.count > 0) {
        for (NSString *error in errors) {
            os_log_error(self.logger, "Configuration update validation error: %{public}@", error);
        }
        return NO;
    }
    
    [self.configuration addEntriesFromDictionary:newConfig];
    
    return [self saveConfiguration];
}

- (BOOL)updateConfigurationValue:(NSString *)key value:(id)value {
    if ([self isForcedByMDM:key]) {
        os_log_error(self.logger, "Cannot update MDM-forced configuration key: %{public}@", key);
        return NO;
    }
    
    self.configuration[key] = value;
    
    return [self saveConfiguration];
}

- (void)resetToDefaults {
    os_log_info(self.logger, "Resetting configuration to defaults");
    self.configuration = [NSMutableDictionary dictionaryWithDictionary:self.defaultConfiguration];
    self.configSource = ConfigurationSourceDefault;
    [self saveConfiguration];
}

- (BOOL)saveConfiguration {
    if (self.configSource == ConfigurationSourceMDMProfile) {
        os_log_info(self.logger, "Configuration is MDM-managed, not saving to disk");
        return YES;
    }
    
    BOOL success = [self.configuration writeToFile:kConfigurationPlistPath atomically:YES];
    if (!success) {
        os_log_error(self.logger, "Failed to save configuration to disk");
    }
    return success;
}

#pragma mark - Configuration Access

- (id)getValueForKey:(NSString *)key defaultValue:(id)defaultValue {
    if (!key) {
        return defaultValue;
    }
    
    id value = self.configuration[key];
    if (value) {
        return value;
    }
    
    return defaultValue;
}

#pragma mark - MDM Profile Support

- (BOOL)isMDMManaged {
    return self.configSource == ConfigurationSourceMDMProfile;
}

- (BOOL)isForcedByMDM:(NSString *)key {
    return CFPreferencesAppValueIsForced((__bridge CFStringRef)key,
                                        (__bridge CFStringRef)kConfigurationDomain);
}

#pragma mark - Configuration Export/Import

- (BOOL)exportConfigurationToFile:(NSString *)path {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.configuration
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:&error];
    if (error) {
        os_log_error(self.logger, "Failed to serialize configuration: %{public}@", error.localizedDescription);
        return NO;
    }
    
    BOOL success = [jsonData writeToFile:path atomically:YES];
    if (!success) {
        os_log_error(self.logger, "Failed to write configuration to file: %{public}@", path);
    }
    return success;
}

- (BOOL)importConfigurationFromFile:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        os_log_error(self.logger, "Configuration file not found: %{public}@", path);
        return NO;
    }
    
    NSError *error = nil;
    NSData *jsonData = [NSData dataWithContentsOfFile:path];
    NSDictionary *importedConfig = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                  options:0
                                                                    error:&error];
    if (error) {
        os_log_error(self.logger, "Failed to parse configuration file: %{public}@", error.localizedDescription);
        return NO;
    }
    
    return [self updateConfiguration:importedConfig];
}

- (NSString *)getConfigurationAsJSON {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.configuration
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:&error];
    if (error) {
        os_log_error(self.logger, "Failed to serialize configuration to JSON: %{public}@", error.localizedDescription);
        return nil;
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

#pragma mark - Validation Methods

- (NSArray *)validateConfigurationValues:(NSDictionary *)config {
    NSMutableArray *errors = [NSMutableArray array];
    
    if (config[@"RotationIntervalDays"]) {
        NSInteger days = [config[@"RotationIntervalDays"] integerValue];
        if (![self isValidRotationInterval:days]) {
            [errors addObject:@"Invalid rotation interval (must be between 1-365 days)"];
        }
    }
    
    if (config[@"MaxKeyAge"]) {
        NSInteger maxAge = [config[@"MaxKeyAge"] integerValue];
        if (maxAge < 1 || maxAge > 730) {
            [errors addObject:@"Invalid maximum key age (must be between 1-730 days)"];
        }
    }
    
    if (config[@"ComplianceStandard"]) {
        if (![self isValidComplianceStandard:config[@"ComplianceStandard"]]) {
            [errors addObject:@"Invalid compliance standard"];
        }
    }
    
    if (config[@"WebhookURL"] && ![config[@"WebhookURL"] isEqualToString:@""]) {
        if (![self isValidWebhookURL:config[@"WebhookURL"]]) {
            [errors addObject:@"Invalid webhook URL"];
        }
    }
    
    return errors;
}

- (BOOL)isValidRotationInterval:(NSInteger)days {
    return days >= 1 && days <= 365;
}

- (BOOL)isValidComplianceStandard:(NSString *)standard {
    NSArray *validStandards = @[@"none", @"NIST", @"ISO27001", @"PCI-DSS", @"HIPAA", @"SOC2"];
    return [validStandards containsObject:standard];
}

- (BOOL)isValidWebhookURL:(NSString *)url {
    NSURL *testURL = [NSURL URLWithString:url];
    if (!testURL || !testURL.scheme || !testURL.host) {
        return NO;
    }
    
    return [testURL.scheme isEqualToString:@"https"] || [testURL.scheme isEqualToString:@"http"];
}

#pragma mark - Property Getters

- (BOOL)autoRotationEnabled {
    return [self.configuration[@"AutoRotationEnabled"] boolValue];
}

- (NSInteger)rotationIntervalDays {
    return [self.configuration[@"RotationIntervalDays"] integerValue];
}

- (BOOL)rotateAfterUse {
    return [self.configuration[@"RotateAfterUse"] boolValue];
}

- (NSInteger)maxKeyAge {
    return [self.configuration[@"MaxKeyAge"] integerValue];
}

- (NSString *)rotationPolicy {
    return self.configuration[@"RotationPolicy"];
}

- (BOOL)enableComplianceReporting {
    return [self.configuration[@"EnableComplianceReporting"] boolValue];
}

- (NSString *)complianceStandard {
    return self.configuration[@"ComplianceStandard"];
}

- (BOOL)enableWebhooks {
    return [self.configuration[@"EnableWebhooks"] boolValue];
}

- (NSString *)webhookURL {
    return self.configuration[@"WebhookURL"];
}

- (BOOL)enableAPIIntegration {
    return [self.configuration[@"EnableAPIIntegration"] boolValue];
}

- (NSString *)jamfServerURL {
    return self.configuration[@"JamfServerURL"];
}

- (BOOL)enableNotifications {
    return [self.configuration[@"EnableNotifications"] boolValue];
}

- (NSInteger)notificationDaysBefore {
    return [self.configuration[@"NotificationDaysBefore"] integerValue];
}

- (BOOL)notifyOnRotationSuccess {
    return [self.configuration[@"NotifyOnRotationSuccess"] boolValue];
}

- (BOOL)notifyOnRotationFailure {
    return [self.configuration[@"NotifyOnRotationFailure"] boolValue];
}

- (BOOL)requireUserAuthentication {
    return [self.configuration[@"RequireUserAuthentication"] boolValue];
}

- (BOOL)allowManualRotation {
    return [self.configuration[@"AllowManualRotation"] boolValue];
}

- (NSInteger)minimumKeyAge {
    return [self.configuration[@"MinimumKeyAge"] integerValue];
}

- (BOOL)enforceKeyComplexity {
    return [self.configuration[@"EnforceKeyComplexity"] boolValue];
}

@end