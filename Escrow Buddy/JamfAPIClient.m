//
//  JamfAPIClient.m
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

#import "JamfAPIClient.h"
#import "EnhancedLogger.h"
#import <IOKit/IOKitLib.h>

static NSString *const kJamfAPIErrorDomain = @"com.netflix.Escrow-Buddy.JamfAPI";
static NSString *const kJamfAPIVersion = @"/api/v1";
static NSString *const kJamfClassicAPI = @"/JSSResource";

@interface JamfAPIClient () <NSURLSessionDelegate>
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) NSString *bearerToken;
@property (nonatomic, strong) NSDate *tokenExpirationDate;
@property (nonatomic, strong) NSString *lastErrorMessage;
@property (nonatomic, strong) NSOperationQueue *sessionQueue;
@property (nonatomic, strong) EnhancedLogger *logger;
@end

@implementation JamfAPIClient

#pragma mark - Singleton

+ (instancetype)sharedClient {
    static JamfAPIClient *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _requestTimeout = 30.0;
        _validateSSLCertificate = YES;
        _authMethod = JamfAPIAuthMethodOAuth;
        _logger = [EnhancedLogger sharedLogger];
        
        [self setupURLSession];
    }
    return self;
}

- (void)setupURLSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = self.requestTimeout;
    config.timeoutIntervalForResource = self.requestTimeout * 2;
    
    self.sessionQueue = [[NSOperationQueue alloc] init];
    self.sessionQueue.maxConcurrentOperationCount = 5;
    
    self.urlSession = [NSURLSession sessionWithConfiguration:config
                                                    delegate:self
                                               delegateQueue:self.sessionQueue];
}

#pragma mark - Authentication

- (void)authenticateWithCompletion:(JamfAPIBoolCompletionHandler)completion {
    if (self.authMethod == JamfAPIAuthMethodBasic) {
        [self authenticateWithUsername:self.username password:self.password completion:completion];
    } else if (self.authMethod == JamfAPIAuthMethodOAuth) {
        [self authenticateOAuthWithCompletion:completion];
    } else if (self.authMethod == JamfAPIAuthMethodAPIToken) {
        [self authenticateWithAPIToken:self.apiToken completion:completion];
    } else {
        NSError *error = [self createErrorWithCode:401 description:@"No authentication method configured"];
        completion(NO, error);
    }
}

- (void)authenticateWithUsername:(NSString *)username 
                         password:(NSString *)password 
                       completion:(JamfAPIBoolCompletionHandler)completion {
    
    self.username = username;
    self.password = password;
    self.authMethod = JamfAPIAuthMethodBasic;
    
    NSString *endpoint = [NSString stringWithFormat:@"%@/auth/token", kJamfAPIVersion];
    
    NSString *credentials = [NSString stringWithFormat:@"%@:%@", username, password];
    NSData *credentialsData = [credentials dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64Credentials = [credentialsData base64EncodedStringWithOptions:0];
    
    NSMutableURLRequest *request = [self createRequestForEndpoint:endpoint method:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Basic %@", base64Credentials] 
   forHTTPHeaderField:@"Authorization"];
    
    [self.logger startPerformanceTimer:@"JamfAuthentication"];
    
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request 
                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        [self.logger endPerformanceTimer:@"JamfAuthentication"];
        
        if (error) {
            [self.logger error:@"Jamf authentication failed" withError:error];
            completion(NO, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        if (httpResponse.statusCode == 200 && data) {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (!jsonError && json[@"token"]) {
                self.bearerToken = json[@"token"];
                
                NSString *expiresString = json[@"expires"];
                if (expiresString) {
                    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
                    [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
                    self.tokenExpirationDate = [formatter dateFromString:expiresString];
                }
                
                [self.logger info:@"Successfully authenticated with Jamf Pro"];
                completion(YES, nil);
            } else {
                NSError *authError = [self createErrorWithCode:401 description:@"Invalid authentication response"];
                completion(NO, authError);
            }
        } else {
            NSError *authError = [self createErrorWithCode:httpResponse.statusCode 
                                               description:@"Authentication failed"];
            completion(NO, authError);
        }
    }];
    
    [task resume];
}

- (void)authenticateOAuthWithCompletion:(JamfAPIBoolCompletionHandler)completion {
    if (!self.username || !self.password) {
        NSError *error = [self createErrorWithCode:401 description:@"Username and password required for OAuth"];
        completion(NO, error);
        return;
    }
    
    [self authenticateWithUsername:self.username password:self.password completion:completion];
}

- (void)authenticateWithAPIToken:(NSString *)apiToken completion:(JamfAPIBoolCompletionHandler)completion {
    self.apiToken = apiToken;
    self.authMethod = JamfAPIAuthMethodAPIToken;
    
    [self.logger info:@"Configured API token authentication"];
    completion(YES, nil);
}

- (void)refreshOAuthTokenWithCompletion:(JamfAPIBoolCompletionHandler)completion {
    if (!self.bearerToken) {
        [self authenticateWithCompletion:completion];
        return;
    }
    
    NSString *endpoint = [NSString stringWithFormat:@"%@/auth/keep-alive", kJamfAPIVersion];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodPOST parameters:nil 
              completion:^(NSDictionary *response, NSError *error) {
        if (!error && response[@"token"]) {
            self.bearerToken = response[@"token"];
            
            NSString *expiresString = response[@"expires"];
            if (expiresString) {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
                [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
                self.tokenExpirationDate = [formatter dateFromString:expiresString];
            }
            
            completion(YES, nil);
        } else {
            completion(NO, error);
        }
    }];
}

- (BOOL)isAuthenticated {
    if (self.authMethod == JamfAPIAuthMethodAPIToken) {
        return self.apiToken != nil;
    }
    
    if (!self.bearerToken) {
        return NO;
    }
    
    if (self.tokenExpirationDate) {
        return [self.tokenExpirationDate compare:[NSDate date]] == NSOrderedDescending;
    }
    
    return YES;
}

- (void)logout {
    if (self.bearerToken) {
        NSString *endpoint = [NSString stringWithFormat:@"%@/auth/invalidate-token", kJamfAPIVersion];
        
        [self makeAPIRequest:endpoint method:JamfAPIRequestMethodPOST parameters:nil 
                  completion:^(NSDictionary *response, NSError *error) {
            [self.logger info:@"Logged out from Jamf Pro"];
        }];
    }
    
    self.bearerToken = nil;
    self.tokenExpirationDate = nil;
    self.oauthToken = nil;
}

#pragma mark - Computer Record Management

- (void)getComputerBySerial:(NSString *)serialNumber completion:(JamfAPICompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/computers/serialnumber/%@", 
                         kJamfClassicAPI, serialNumber];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil completion:completion];
}

- (void)getComputerByID:(NSInteger)computerID completion:(JamfAPICompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/computers/id/%ld", 
                         kJamfClassicAPI, (long)computerID];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil completion:completion];
}

- (void)getComputerByUDID:(NSString *)udid completion:(JamfAPICompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/computers/udid/%@", 
                         kJamfClassicAPI, udid];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil completion:completion];
}

- (void)getCurrentComputerWithCompletion:(JamfAPICompletionHandler)completion {
    NSString *serialNumber = [self getComputerSerialNumber];
    
    if (!serialNumber) {
        NSError *error = [self createErrorWithCode:404 description:@"Could not determine computer serial number"];
        completion(nil, error);
        return;
    }
    
    [self getComputerBySerial:serialNumber completion:completion];
}

#pragma mark - FileVault Key Management

- (void)verifyKeyEscrowSuccess:(NSString *)keyID completion:(JamfAPIBoolCompletionHandler)completion {
    [self getCurrentComputerWithCompletion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSDictionary *computer = response[@"computer"];
        NSDictionary *filevault = computer[@"hardware"][@"filevault2_users"];
        
        BOOL keyEscrowed = NO;
        if (filevault && filevault.count > 0) {
            for (NSDictionary *user in filevault) {
                if ([user[@"filevault_enabled"] boolValue]) {
                    keyEscrowed = YES;
                    break;
                }
            }
        }
        
        if (keyEscrowed) {
            [self.logger logKeyLifecycleEvent:@"EscrowVerified" keyID:keyID status:@"Success"];
        } else {
            [self.logger logKeyLifecycleEvent:@"EscrowVerified" keyID:keyID status:@"Failed"];
        }
        
        completion(keyEscrowed, nil);
    }];
}

- (void)getFileVaultStatusForComputer:(NSInteger)computerID completion:(JamfAPICompletionHandler)completion {
    [self getComputerByID:computerID completion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSDictionary *computer = response[@"computer"];
        NSDictionary *hardware = computer[@"hardware"];
        
        NSMutableDictionary *filevaultStatus = [NSMutableDictionary dictionary];
        filevaultStatus[@"disk_encryption_configuration"] = hardware[@"disk_encryption_configuration"];
        filevaultStatus[@"filevault_status"] = hardware[@"filevault_status"];
        filevaultStatus[@"filevault_percent"] = hardware[@"filevault_percent"];
        filevaultStatus[@"filevault2_users"] = hardware[@"filevault2_users"];
        
        completion(filevaultStatus, nil);
    }];
}

- (void)getRecoveryKeyForComputer:(NSInteger)computerID completion:(JamfAPICompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/computers/id/%ld/filevaultkey", 
                         kJamfClassicAPI, (long)computerID];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil completion:completion];
}

- (void)validateRecoveryKeyForComputer:(NSInteger)computerID 
                                    key:(NSString *)recoveryKey 
                             completion:(JamfAPIBoolCompletionHandler)completion {
    
    NSString *endpoint = [NSString stringWithFormat:@"%@/computers/id/%ld/filevaultkey/verify", 
                         kJamfClassicAPI, (long)computerID];
    
    NSDictionary *parameters = @{@"recovery_key": recoveryKey};
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodPOST parameters:parameters 
              completion:^(NSDictionary *response, NSError *error) {
        completion(error == nil, error);
    }];
}

#pragma mark - Extension Attributes

- (void)updateExtensionAttribute:(NSString *)attributeName 
                           value:(NSString *)value 
                    forComputerID:(NSInteger)computerID 
                      completion:(JamfAPIBoolCompletionHandler)completion {
    
    NSString *endpoint = [NSString stringWithFormat:@"%@/computers/id/%ld", 
                         kJamfClassicAPI, (long)computerID];
    
    NSDictionary *extensionAttribute = @{
        @"name": attributeName,
        @"value": value
    };
    
    NSDictionary *parameters = @{
        @"computer": @{
            @"extension_attributes": @[extensionAttribute]
        }
    };
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodPUT parameters:parameters 
              completion:^(NSDictionary *response, NSError *error) {
        completion(error == nil, error);
    }];
}

- (void)getExtensionAttributeValue:(NSString *)attributeName 
                      forComputerID:(NSInteger)computerID 
                         completion:(JamfAPICompletionHandler)completion {
    
    [self getComputerByID:computerID completion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSDictionary *computer = response[@"computer"];
        NSArray *extensionAttributes = computer[@"extension_attributes"];
        
        for (NSDictionary *attribute in extensionAttributes) {
            if ([attribute[@"name"] isEqualToString:attributeName]) {
                completion(@{@"value": attribute[@"value"]}, nil);
                return;
            }
        }
        
        NSError *notFoundError = [self createErrorWithCode:404 
                                               description:@"Extension attribute not found"];
        completion(nil, notFoundError);
    }];
}

#pragma mark - Smart Group Management

- (void)isComputerInSmartGroup:(NSString *)groupName 
                     computerID:(NSInteger)computerID 
                     completion:(JamfAPIBoolCompletionHandler)completion {
    
    NSString *endpoint = [NSString stringWithFormat:@"%@/computergroups/name/%@", 
                         kJamfClassicAPI, 
                         [groupName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil 
              completion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSDictionary *group = response[@"computer_group"];
        NSArray *computers = group[@"computers"];
        
        BOOL isMember = NO;
        for (NSDictionary *computer in computers) {
            if ([computer[@"id"] integerValue] == computerID) {
                isMember = YES;
                break;
            }
        }
        
        completion(isMember, nil);
    }];
}

- (void)getSmartGroupMembers:(NSString *)groupName completion:(JamfAPICompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/computergroups/name/%@", 
                         kJamfClassicAPI, 
                         [groupName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil completion:completion];
}

- (void)getSmartGroupsForComputer:(NSInteger)computerID completion:(JamfAPICompletionHandler)completion {
    [self getComputerByID:computerID completion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSDictionary *computer = response[@"computer"];
        NSArray *groups = computer[@"groups_accounts"][@"computer_group_memberships"];
        
        completion(@{@"groups": groups ?: @[]}, nil);
    }];
}

#pragma mark - Reporting

- (void)reportRotationEvent:(NSDictionary *)eventData completion:(JamfAPIBoolCompletionHandler)completion {
    NSString *serialNumber = [self getComputerSerialNumber];
    
    [self getCurrentComputerWithCompletion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSDictionary *computer = response[@"computer"];
        NSInteger computerID = [computer[@"general"][@"id"] integerValue];
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        
        NSString *rotationStatus = [NSString stringWithFormat:@"Rotated: %@ - Reason: %@", 
                                  timestamp, 
                                  eventData[@"reason"] ?: @"Unknown"];
        
        [self updateExtensionAttribute:@"FileVault_Key_Rotation_Status" 
                                 value:rotationStatus 
                          forComputerID:computerID 
                            completion:completion];
    }];
}

- (void)reportComplianceStatus:(NSDictionary *)complianceData completion:(JamfAPIBoolCompletionHandler)completion {
    [self getCurrentComputerWithCompletion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSDictionary *computer = response[@"computer"];
        NSInteger computerID = [computer[@"general"][@"id"] integerValue];
        
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:complianceData 
                                                          options:0 
                                                            error:&jsonError];
        
        if (jsonError) {
            completion(NO, jsonError);
            return;
        }
        
        NSString *complianceJSON = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        
        [self updateExtensionAttribute:@"FileVault_Compliance_Status" 
                                 value:complianceJSON 
                          forComputerID:computerID 
                            completion:completion];
    }];
}

- (void)submitInventoryUpdate:(NSInteger)computerID completion:(JamfAPIBoolCompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/computers/id/%ld/command/UpdateInventory", 
                         kJamfClassicAPI, (long)computerID];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodPOST parameters:nil 
              completion:^(NSDictionary *response, NSError *error) {
        completion(error == nil, error);
    }];
}

#pragma mark - Policy Management

- (void)getPolicyByName:(NSString *)policyName completion:(JamfAPICompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/policies/name/%@", 
                         kJamfClassicAPI, 
                         [policyName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil completion:completion];
}

- (void)getPolicyByID:(NSInteger)policyID completion:(JamfAPICompletionHandler)completion {
    NSString *endpoint = [NSString stringWithFormat:@"%@/policies/id/%ld", 
                         kJamfClassicAPI, (long)policyID];
    
    [self makeAPIRequest:endpoint method:JamfAPIRequestMethodGET parameters:nil completion:completion];
}

- (void)executePolicyByEvent:(NSString *)eventName 
                  computerID:(NSInteger)computerID 
                  completion:(JamfAPIBoolCompletionHandler)completion {
    
    NSError *error = [self createErrorWithCode:501 
                                   description:@"Policy execution requires jamf binary on client"];
    completion(NO, error);
}

#pragma mark - Configuration Profiles

- (void)getConfigurationProfilesForComputer:(NSInteger)computerID completion:(JamfAPICompletionHandler)completion {
    [self getComputerByID:computerID completion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        
        NSDictionary *computer = response[@"computer"];
        NSArray *profiles = computer[@"configuration_profiles"];
        
        completion(@{@"profiles": profiles ?: @[]}, nil);
    }];
}

- (void)isProfileInstalled:(NSString *)profileIdentifier 
                computerID:(NSInteger)computerID 
                completion:(JamfAPIBoolCompletionHandler)completion {
    
    [self getConfigurationProfilesForComputer:computerID completion:^(NSDictionary *response, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSArray *profiles = response[@"profiles"];
        BOOL isInstalled = NO;
        
        for (NSDictionary *profile in profiles) {
            if ([profile[@"uuid"] isEqualToString:profileIdentifier] || 
                [profile[@"name"] isEqualToString:profileIdentifier]) {
                isInstalled = YES;
                break;
            }
        }
        
        completion(isInstalled, nil);
    }];
}

#pragma mark - Webhook Integration

- (void)sendWebhookNotification:(NSDictionary *)payload 
                      webhookURL:(NSString *)webhookURL 
                      completion:(JamfAPIBoolCompletionHandler)completion {
    
    NSURL *url = [NSURL URLWithString:webhookURL];
    if (!url) {
        NSError *error = [self createErrorWithCode:400 description:@"Invalid webhook URL"];
        completion(NO, error);
        return;
    }
    
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload 
                                                      options:0 
                                                        error:&jsonError];
    if (jsonError) {
        completion(NO, jsonError);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:jsonData];
    [request setTimeoutInterval:self.requestTimeout];
    
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request 
                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(NO, error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        BOOL success = (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300);
        
        if (!success) {
            NSError *webhookError = [self createErrorWithCode:httpResponse.statusCode 
                                                  description:@"Webhook request failed"];
            completion(NO, webhookError);
        } else {
            completion(YES, nil);
        }
    }];
    
    [task resume];
}

#pragma mark - Generic API Methods

- (void)makeAPIRequest:(NSString *)endpoint 
                method:(JamfAPIRequestMethod)method 
            parameters:(NSDictionary *)parameters 
            completion:(JamfAPICompletionHandler)completion {
    
    if (![self isAuthenticated] && self.authMethod != JamfAPIAuthMethodAPIToken) {
        [self authenticateWithCompletion:^(BOOL success, NSError *error) {
            if (success) {
                [self makeAPIRequest:endpoint method:method parameters:parameters completion:completion];
            } else {
                completion(nil, error);
            }
        }];
        return;
    }
    
    NSMutableURLRequest *request = [self createRequestForEndpoint:endpoint 
                                                            method:[self stringForMethod:method]];
    
    if (self.bearerToken) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.bearerToken] 
       forHTTPHeaderField:@"Authorization"];
    } else if (self.apiToken) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiToken] 
       forHTTPHeaderField:@"Authorization"];
    }
    
    if (parameters && (method == JamfAPIRequestMethodPOST || 
                      method == JamfAPIRequestMethodPUT || 
                      method == JamfAPIRequestMethodPATCH)) {
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters 
                                                          options:0 
                                                            error:&jsonError];
        if (jsonError) {
            completion(nil, jsonError);
            return;
        }
        
        [request setHTTPBody:jsonData];
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    
    NSDate *startTime = [NSDate date];
    
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request 
                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:startTime];
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        
        [self.logger logAPICall:endpoint 
                         method:[self stringForMethod:method] 
                       response:httpResponse.statusCode 
                       duration:duration];
        
        if (error) {
            completion(nil, error);
            return;
        }
        
        if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
            if (data && data.length > 0) {
                NSError *jsonError;
                id jsonResponse = [NSJSONSerialization JSONObjectWithData:data 
                                                                  options:0 
                                                                    error:&jsonError];
                if (jsonError) {
                    completion(nil, jsonError);
                } else {
                    completion(jsonResponse, nil);
                }
            } else {
                completion(@{}, nil);
            }
        } else {
            NSString *errorMessage = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSError *apiError = [self createErrorWithCode:httpResponse.statusCode 
                                              description:errorMessage ?: @"API request failed"];
            completion(nil, apiError);
        }
    }];
    
    [task resume];
}

- (void)makeRawAPIRequest:(NSString *)endpoint 
                   method:(JamfAPIRequestMethod)method 
                     body:(NSData *)body 
               completion:(JamfAPIDataCompletionHandler)completion {
    
    NSMutableURLRequest *request = [self createRequestForEndpoint:endpoint 
                                                            method:[self stringForMethod:method]];
    
    if (self.bearerToken) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", self.bearerToken] 
       forHTTPHeaderField:@"Authorization"];
    }
    
    if (body) {
        [request setHTTPBody:body];
    }
    
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request 
                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        completion(data, error);
    }];
    
    [task resume];
}

#pragma mark - Utility Methods

- (NSString *)getComputerSerialNumber {
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                             IOServiceMatching("IOPlatformExpertDevice"));
    
    if (!platformExpert) return nil;
    
    CFStringRef serialNumberRef = (CFStringRef)IORegistryEntryCreateCFProperty(platformExpert,
                                                                              CFSTR(kIOPlatformSerialNumberKey),
                                                                              kCFAllocatorDefault,
                                                                              0);
    IOObjectRelease(platformExpert);
    
    if (!serialNumberRef) return nil;
    
    NSString *serialNumber = (__bridge_transfer NSString *)serialNumberRef;
    return serialNumber;
}

- (NSString *)getComputerUDID {
    io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
    
    if (!ioRegistryRoot) return nil;
    
    CFStringRef uuidRef = (CFStringRef)IORegistryEntryCreateCFProperty(ioRegistryRoot,
                                                                       CFSTR(kIOPlatformUUIDKey),
                                                                       kCFAllocatorDefault,
                                                                       0);
    IOObjectRelease(ioRegistryRoot);
    
    if (!uuidRef) return nil;
    
    NSString *uuid = (__bridge_transfer NSString *)uuidRef;
    return uuid;
}

- (NSString *)getComputerName {
    return [[NSHost currentHost] localizedName];
}

- (NSDictionary *)getSystemInfo {
    return @{
        @"serialNumber": [self getComputerSerialNumber] ?: @"Unknown",
        @"udid": [self getComputerUDID] ?: @"Unknown",
        @"computerName": [self getComputerName] ?: @"Unknown",
        @"osVersion": [[NSProcessInfo processInfo] operatingSystemVersionString]
    };
}

- (BOOL)isJamfManaged {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/local/jamf/bin/jamf"];
}

#pragma mark - Helper Methods

- (NSMutableURLRequest *)createRequestForEndpoint:(NSString *)endpoint method:(NSString *)method {
    NSString *fullURL = [NSString stringWithFormat:@"%@%@", self.serverURL, endpoint];
    NSURL *url = [NSURL URLWithString:fullURL];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:method];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setTimeoutInterval:self.requestTimeout];
    
    return request;
}

- (NSString *)stringForMethod:(JamfAPIRequestMethod)method {
    switch (method) {
        case JamfAPIRequestMethodGET: return @"GET";
        case JamfAPIRequestMethodPOST: return @"POST";
        case JamfAPIRequestMethodPUT: return @"PUT";
        case JamfAPIRequestMethodDELETE: return @"DELETE";
        case JamfAPIRequestMethodPATCH: return @"PATCH";
        default: return @"GET";
    }
}

#pragma mark - Error Handling

- (NSError *)createErrorWithCode:(NSInteger)code description:(NSString *)description {
    self.lastErrorMessage = description;
    
    return [NSError errorWithDomain:kJamfAPIErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (BOOL)handleAPIError:(NSError *)error {
    [self.logger error:@"Jamf API Error" withError:error];
    
    if (error.code == 401) {
        self.bearerToken = nil;
        self.tokenExpirationDate = nil;
        return YES;
    }
    
    return NO;
}

- (NSString *)getLastErrorMessage {
    return self.lastErrorMessage;
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session 
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge 
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    
    if (!self.validateSSLCertificate) {
        NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

@end