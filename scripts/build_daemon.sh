#!/bin/bash

#
#  build_daemon.sh
#  Escrow Buddy Enhanced
#
#  Builds the EscrowBuddyDaemon executable
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"
OUTPUT_DIR="${PROJECT_ROOT}/dist"

echo "Building Escrow Buddy Daemon..."

# Create build directory
mkdir -p "${BUILD_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Compile daemon
clang -framework Foundation \
      -framework Security \
      -framework IOKit \
      -fobjc-arc \
      -O2 \
      -o "${BUILD_DIR}/EscrowBuddyDaemon" \
      "${PROJECT_ROOT}/Escrow Buddy/EscrowBuddyDaemon/main.m" \
      "${PROJECT_ROOT}/Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyDaemon.m" \
      "${PROJECT_ROOT}/Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyXPCClient.m" \
      "${PROJECT_ROOT}/Escrow Buddy/RotationManager.m" \
      "${PROJECT_ROOT}/Escrow Buddy/ConfigurationManager.m" \
      "${PROJECT_ROOT}/Escrow Buddy/KeyLifecycleTracker.m" \
      "${PROJECT_ROOT}/Escrow Buddy/EnhancedLogger.m" \
      "${PROJECT_ROOT}/Escrow Buddy/ComplianceReporter.m" \
      "${PROJECT_ROOT}/Escrow Buddy/JamfAPIClient.m"

# Sign daemon if identity provided
if [ -n "$1" ]; then
    echo "Signing daemon with identity: $1"
    codesign --force --sign "$1" \
             --timestamp \
             --options runtime \
             --entitlements "${PROJECT_ROOT}/Escrow Buddy/EscrowBuddyDaemon/entitlements.plist" \
             "${BUILD_DIR}/EscrowBuddyDaemon"
fi

echo "Daemon built successfully: ${BUILD_DIR}/EscrowBuddyDaemon"