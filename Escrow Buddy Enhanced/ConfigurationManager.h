//
//  ConfigurationManager.h
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

typedef NS_ENUM(NSInteger, ConfigurationSource) {
    ConfigurationSourceDefault = 0,
    ConfigurationSourcePlist,
    ConfigurationSourceMDMProfile,
    ConfigurationSourceCLI
};

@interface ConfigurationManager : NSObject

#pragma mark - Core Rotation Settings

@property (nonatomic, readonly) BOOL autoRotationEnabled;
@property (nonatomic, readonly) NSInteger rotationIntervalDays;
@property (nonatomic, readonly) BOOL rotateAfterUse;
@property (nonatomic, readonly) NSInteger maxKeyAge;
@property (nonatomic, readonly) NSString *rotationPolicy;

#pragma mark - Advanced Settings

@property (nonatomic, readonly) BOOL enableComplianceReporting;
@property (nonatomic, readonly) NSString *complianceStandard;
@property (nonatomic, readonly) BOOL enableWebhooks;
@property (nonatomic, readonly) NSString * _Nullable webhookURL;
@property (nonatomic, readonly) BOOL enableAPIIntegration;
@property (nonatomic, readonly) NSString * _Nullable jamfServerURL;

#pragma mark - Notification Settings

@property (nonatomic, readonly) BOOL enableNotifications;
@property (nonatomic, readonly) NSInteger notificationDaysBefore;
@property (nonatomic, readonly) BOOL notifyOnRotationSuccess;
@property (nonatomic, readonly) BOOL notifyOnRotationFailure;

#pragma mark - Security Settings

@property (nonatomic, readonly) BOOL requireUserAuthentication;
@property (nonatomic, readonly) BOOL allowManualRotation;
@property (nonatomic, readonly) NSInteger minimumKeyAge;
@property (nonatomic, readonly) BOOL enforceKeyComplexity;

#pragma mark - Singleton

+ (instancetype)sharedManager;

#pragma mark - Configuration Management

- (void)loadConfiguration;
- (void)reloadConfiguration;
- (BOOL)validateConfiguration;
- (NSDictionary *)getCurrentConfiguration;
- (ConfigurationSource)getConfigurationSource;

#pragma mark - Configuration Updates

- (BOOL)updateConfiguration:(NSDictionary *)newConfig;
- (BOOL)updateConfigurationValue:(NSString *)key value:(id)value;
- (void)resetToDefaults;

#pragma mark - Configuration Access

- (id)getValueForKey:(NSString *)key defaultValue:(id)defaultValue;

#pragma mark - MDM Profile Support

- (BOOL)isMDMManaged;
- (NSDictionary * _Nullable)getMDMConfiguration;
- (BOOL)isForcedByMDM:(NSString *)key;

#pragma mark - Configuration Export/Import

- (BOOL)exportConfigurationToFile:(NSString *)path;
- (BOOL)importConfigurationFromFile:(NSString *)path;
- (NSString *)getConfigurationAsJSON;

#pragma mark - Validation

- (NSArray *)validateConfigurationValues:(NSDictionary *)config;
- (BOOL)isValidRotationInterval:(NSInteger)days;
- (BOOL)isValidComplianceStandard:(NSString *)standard;
- (BOOL)isValidWebhookURL:(NSString *)url;

@end

NS_ASSUME_NONNULL_END