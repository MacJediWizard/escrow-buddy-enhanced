//
//  JamfAPIClient.h
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

typedef NS_ENUM(NSInteger, JamfAPIAuthMethod) {
    JamfAPIAuthMethodBasic = 0,
    JamfAPIAuthMethodOAuth,
    JamfAPIAuthMethodAPIToken
};

typedef NS_ENUM(NSInteger, JamfAPIRequestMethod) {
    JamfAPIRequestMethodGET = 0,
    JamfAPIRequestMethodPOST,
    JamfAPIRequestMethodPUT,
    JamfAPIRequestMethodDELETE,
    JamfAPIRequestMethodPATCH
};

typedef void (^JamfAPICompletionHandler)(NSDictionary * _Nullable response, NSError * _Nullable error);
typedef void (^JamfAPIBoolCompletionHandler)(BOOL success, NSError * _Nullable error);
typedef void (^JamfAPIDataCompletionHandler)(NSData * _Nullable data, NSError * _Nullable error);

@interface JamfAPIClient : NSObject

#pragma mark - Configuration

@property (nonatomic, strong) NSString *serverURL;
@property (nonatomic, strong) NSString * _Nullable username;
@property (nonatomic, strong) NSString * _Nullable password;
@property (nonatomic, strong) NSString * _Nullable apiToken;
@property (nonatomic, strong) NSString * _Nullable oauthToken;
@property (nonatomic, assign) JamfAPIAuthMethod authMethod;
@property (nonatomic, assign) NSTimeInterval requestTimeout;
@property (nonatomic, assign) BOOL validateSSLCertificate;

#pragma mark - Singleton

+ (instancetype)sharedClient;

#pragma mark - Authentication

- (void)authenticateWithCompletion:(JamfAPIBoolCompletionHandler)completion;
- (void)authenticateWithUsername:(NSString *)username 
                         password:(NSString *)password 
                       completion:(JamfAPIBoolCompletionHandler)completion;
- (void)authenticateWithAPIToken:(NSString *)apiToken 
                      completion:(JamfAPIBoolCompletionHandler)completion;
- (void)refreshOAuthTokenWithCompletion:(JamfAPIBoolCompletionHandler)completion;
- (BOOL)isAuthenticated;
- (void)logout;

#pragma mark - Computer Record Management

- (void)getComputerBySerial:(NSString *)serialNumber 
                 completion:(JamfAPICompletionHandler)completion;
- (void)getComputerByID:(NSInteger)computerID 
             completion:(JamfAPICompletionHandler)completion;
- (void)getComputerByUDID:(NSString *)udid 
               completion:(JamfAPICompletionHandler)completion;
- (void)getCurrentComputerWithCompletion:(JamfAPICompletionHandler)completion;

#pragma mark - FileVault Key Management

- (void)verifyKeyEscrowSuccess:(NSString *)keyID 
                    completion:(JamfAPIBoolCompletionHandler)completion;
- (void)getFileVaultStatusForComputer:(NSInteger)computerID 
                           completion:(JamfAPICompletionHandler)completion;
- (void)getRecoveryKeyForComputer:(NSInteger)computerID 
                       completion:(JamfAPICompletionHandler)completion;
- (void)validateRecoveryKeyForComputer:(NSInteger)computerID 
                                    key:(NSString *)recoveryKey 
                             completion:(JamfAPIBoolCompletionHandler)completion;

#pragma mark - Extension Attributes

- (void)updateExtensionAttribute:(NSString *)attributeName 
                           value:(NSString *)value 
                    forComputerID:(NSInteger)computerID 
                      completion:(JamfAPIBoolCompletionHandler)completion;
- (void)getExtensionAttributeValue:(NSString *)attributeName 
                      forComputerID:(NSInteger)computerID 
                         completion:(JamfAPICompletionHandler)completion;

#pragma mark - Smart Group Management

- (void)isComputerInSmartGroup:(NSString *)groupName 
                     computerID:(NSInteger)computerID 
                     completion:(JamfAPIBoolCompletionHandler)completion;
- (void)getSmartGroupMembers:(NSString *)groupName 
                  completion:(JamfAPICompletionHandler)completion;
- (void)getSmartGroupsForComputer:(NSInteger)computerID 
                        completion:(JamfAPICompletionHandler)completion;

#pragma mark - Reporting

- (void)reportRotationEvent:(NSDictionary *)eventData 
                 completion:(JamfAPIBoolCompletionHandler)completion;
- (void)reportComplianceStatus:(NSDictionary *)complianceData 
                    completion:(JamfAPIBoolCompletionHandler)completion;
- (void)submitInventoryUpdate:(NSInteger)computerID 
                   completion:(JamfAPIBoolCompletionHandler)completion;

#pragma mark - Policy Management

- (void)getPolicyByName:(NSString *)policyName 
             completion:(JamfAPICompletionHandler)completion;
- (void)getPolicyByID:(NSInteger)policyID 
           completion:(JamfAPICompletionHandler)completion;
- (void)executePolicyByEvent:(NSString *)eventName 
                  computerID:(NSInteger)computerID 
                  completion:(JamfAPIBoolCompletionHandler)completion;

#pragma mark - Configuration Profiles

- (void)getConfigurationProfilesForComputer:(NSInteger)computerID 
                                 completion:(JamfAPICompletionHandler)completion;
- (void)isProfileInstalled:(NSString *)profileIdentifier 
                computerID:(NSInteger)computerID 
                completion:(JamfAPIBoolCompletionHandler)completion;

#pragma mark - Webhook Integration

- (void)sendWebhookNotification:(NSDictionary *)payload 
                      webhookURL:(NSString *)webhookURL 
                      completion:(JamfAPIBoolCompletionHandler)completion;

#pragma mark - Generic API Methods

- (void)makeAPIRequest:(NSString *)endpoint 
                method:(JamfAPIRequestMethod)method 
            parameters:(NSDictionary * _Nullable)parameters 
            completion:(JamfAPICompletionHandler)completion;

- (void)makeRawAPIRequest:(NSString *)endpoint 
                   method:(JamfAPIRequestMethod)method 
                     body:(NSData * _Nullable)body 
               completion:(JamfAPIDataCompletionHandler)completion;

#pragma mark - Utility Methods

- (NSString *)getComputerSerialNumber;
- (NSString *)getComputerUDID;
- (NSString *)getComputerName;
- (NSDictionary *)getSystemInfo;
- (BOOL)isJamfManaged;

#pragma mark - Error Handling

- (NSError *)createErrorWithCode:(NSInteger)code 
                      description:(NSString *)description;
- (BOOL)handleAPIError:(NSError *)error;
- (NSString *)getLastErrorMessage;

@end

NS_ASSUME_NONNULL_END