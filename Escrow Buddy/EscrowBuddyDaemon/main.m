//
//  main.m
//  EscrowBuddyDaemon
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
#import "EscrowBuddyDaemon.h"
#import <os/log.h>
#import <signal.h>

static EscrowBuddyDaemon *escrowDaemon = nil;
static BOOL shouldKeepRunning = YES;
static os_log_t logger = nil;

void signalHandler(int signal) {
    os_log_info(logger, "Received signal %d", signal);
    
    switch (signal) {
        case SIGTERM:
        case SIGINT:
            os_log_info(logger, "Shutting down daemon");
            shouldKeepRunning = NO;
            if (escrowDaemon) {
                [escrowDaemon stopDaemon];
            }
            break;
            
        case SIGHUP:
            os_log_info(logger, "Reloading configuration");
            if (escrowDaemon) {
                [escrowDaemon reloadConfiguration];
            }
            break;
            
        case SIGUSR1:
            os_log_info(logger, "Performing immediate rotation check");
            if (escrowDaemon) {
                [escrowDaemon performBackgroundRotationWithCompletion:nil];
            }
            break;
            
        default:
            break;
    }
}

void setupSignalHandlers() {
    signal(SIGTERM, signalHandler);
    signal(SIGINT, signalHandler);
    signal(SIGHUP, signalHandler);
    signal(SIGUSR1, signalHandler);
    signal(SIGPIPE, SIG_IGN);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        logger = os_log_create("com.netflix.Escrow-Buddy", "DaemonMain");
        
        os_log_info(logger, "Escrow Buddy Daemon starting");
        os_log_info(logger, "Version: 1.0.0");
        os_log_info(logger, "PID: %d", getpid());
        
        // Check if running as root
        if (geteuid() != 0) {
            os_log_error(logger, "Daemon must run as root (current UID: %d)", geteuid());
            return 1;
        }
        
        // Parse command line arguments
        BOOL debugMode = NO;
        BOOL oneShot = NO;
        
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--debug") == 0 || strcmp(argv[i], "-d") == 0) {
                debugMode = YES;
            } else if (strcmp(argv[i], "--once") == 0 || strcmp(argv[i], "-o") == 0) {
                oneShot = YES;
            } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
                printf("Escrow Buddy Daemon\n");
                printf("Usage: %s [options]\n", argv[0]);
                printf("Options:\n");
                printf("  -d, --debug    Enable debug mode\n");
                printf("  -o, --once     Run once and exit\n");
                printf("  -h, --help     Show this help message\n");
                return 0;
            }
        }
        
        // Set up signal handlers
        setupSignalHandlers();
        
        // Create and start the daemon
        escrowDaemon = [EscrowBuddyDaemon sharedDaemon];
        
        if (debugMode) {
            [escrowDaemon enableDebugMode:YES];
            os_log_info(logger, "Debug mode enabled");
        }
        
        // Start the daemon
        [escrowDaemon startDaemon];
        
        if (oneShot) {
            // Run once mode - perform immediate check and exit
            os_log_info(logger, "Running in one-shot mode");
            
            if ([escrowDaemon isRotationNeeded]) {
                os_log_info(logger, "Rotation needed, performing rotation");
                [escrowDaemon performBackgroundRotation];
            } else {
                os_log_info(logger, "No rotation needed");
            }
            
            [escrowDaemon stopDaemon];
            return 0;
        }
        
        // Create run loop
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        
        // Keep the daemon running
        while (shouldKeepRunning && [runLoop runMode:NSDefaultRunLoopMode 
                                          beforeDate:[NSDate distantFuture]]) {
            // Run loop will handle timer events and XPC messages
        }
        
        os_log_info(logger, "Daemon shutting down");
        
        // Clean shutdown
        if (escrowDaemon) {
            [escrowDaemon stopDaemon];
        }
        
        os_log_info(logger, "Daemon terminated");
    }
    
    return 0;
}