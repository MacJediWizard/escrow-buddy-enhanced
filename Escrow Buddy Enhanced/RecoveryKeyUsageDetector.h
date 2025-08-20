/**
 * RecoveryKeyUsageDetector.h
 * Escrow Buddy Enhanced
 *
 * Detects when a FileVault recovery key has been used for unlock
 * and triggers automatic rotation if configured.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Detection methods for recovery key usage
 */
typedef NS_ENUM(NSInteger, RecoveryKeyDetectionMethod) {
    RecoveryKeyDetectionMethodNone = 0,
    RecoveryKeyDetectionMethodAuthLog = 1,      // Monitor auth.log for recovery key events
    RecoveryKeyDetectionMethodFDERecovery = 2,  // Check FDE recovery status
    RecoveryKeyDetectionMethodLoginWindow = 3,  // Monitor login window events
    RecoveryKeyDetectionMethodAll = 4           // Use all available methods
};

/**
 * Notification sent when recovery key usage is detected
 */
extern NSString * const RecoveryKeyUsedNotification;

/**
 * Keys for notification userInfo dictionary
 */
extern NSString * const RecoveryKeyUsedDateKey;
extern NSString * const RecoveryKeyUsedMethodKey;
extern NSString * const RecoveryKeyUsedUserKey;

@class RotationManager;
@class KeyLifecycleTracker;

/**
 * RecoveryKeyUsageDetector
 * 
 * Monitors system events to detect when a FileVault recovery key
 * has been used to unlock the disk. When detected, marks the key
 * as used and optionally triggers rotation.
 */
@interface RecoveryKeyUsageDetector : NSObject

/**
 * Shared singleton instance
 */
+ (instancetype)sharedDetector;

/**
 * Initialize with rotation manager and lifecycle tracker
 */
- (instancetype)initWithRotationManager:(RotationManager *)rotationManager
                      lifecycleTracker:(KeyLifecycleTracker *)lifecycleTracker;

/**
 * Start monitoring for recovery key usage
 */
- (void)startMonitoring;

/**
 * Stop monitoring
 */
- (void)stopMonitoring;

/**
 * Check if recovery key was used in current session
 * @return YES if recovery key was used, NO otherwise
 */
- (BOOL)wasRecoveryKeyUsedInCurrentSession;

/**
 * Check if recovery key was used since a given date
 * @param date The date to check from
 * @return YES if recovery key was used since date, NO otherwise
 */
- (BOOL)wasRecoveryKeyUsedSinceDate:(NSDate *)date;

/**
 * Manually check for recovery key usage (immediate check)
 * @return YES if recovery key usage detected, NO otherwise
 */
- (BOOL)checkForRecoveryKeyUsage;

/**
 * Get the last date/time recovery key was used
 * @return Date of last usage or nil if never used
 */
- (nullable NSDate *)lastRecoveryKeyUsageDate;

/**
 * Configuration
 */
@property (nonatomic, assign) RecoveryKeyDetectionMethod detectionMethod;
@property (nonatomic, assign) BOOL autoMarkAsUsed;  // Automatically mark key as used when detected
@property (nonatomic, assign) BOOL triggerRotation; // Automatically trigger rotation when detected
@property (nonatomic, assign) NSTimeInterval checkInterval; // How often to check (default: 300 seconds)

/**
 * Status
 */
@property (nonatomic, readonly) BOOL isMonitoring;
@property (nonatomic, readonly) NSInteger detectionCount;
@property (nonatomic, readonly) NSDate *lastCheckDate;

@end

NS_ASSUME_NONNULL_END