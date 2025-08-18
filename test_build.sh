#!/bin/bash

#
#  test_build.sh
#  Test compilation of all components
#

set -e

echo "=== Testing Escrow Buddy Enhanced Build ==="
echo

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}1. Testing Objective-C compilation...${NC}"
echo "----------------------------------------"

# Test compile each Objective-C file
OBJ_C_FILES=(
    "Escrow Buddy/RotationManager.m"
    "Escrow Buddy/ConfigurationManager.m"
    "Escrow Buddy/KeyLifecycleTracker.m"
    "Escrow Buddy/EnhancedLogger.m"
    "Escrow Buddy/JamfAPIClient.m"
    "Escrow Buddy/ComplianceReporter.m"
    "Escrow Buddy/EBAuthPlugin.m"
)

for file in "${OBJ_C_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -n "Testing $(basename "$file")... "
        if clang -c -fobjc-arc -framework Foundation -framework Security \
                -I"Escrow Buddy" -I"Escrow Buddy/EscrowBuddyDaemon" \
                "$file" -o /tmp/test.o 2>/tmp/compile_errors.txt; then
            echo -e "${GREEN}✅${NC}"
            rm -f /tmp/test.o
        else
            echo -e "${RED}❌${NC}"
            echo "Errors:"
            head -5 /tmp/compile_errors.txt
        fi
    fi
done

echo
echo -e "${YELLOW}2. Testing Daemon compilation...${NC}"
echo "----------------------------------------"

DAEMON_FILES=(
    "Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyDaemon.m"
    "Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyXPCClient.m"
    "Escrow Buddy/EscrowBuddyDaemon/main.m"
)

for file in "${DAEMON_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -n "Testing $(basename "$file")... "
        if clang -c -fobjc-arc -framework Foundation -framework Security \
                -I"Escrow Buddy" -I"Escrow Buddy/EscrowBuddyDaemon" \
                "$file" -o /tmp/test.o 2>/tmp/compile_errors.txt; then
            echo -e "${GREEN}✅${NC}"
            rm -f /tmp/test.o
        else
            echo -e "${RED}❌${NC}"
            echo "Errors:"
            head -5 /tmp/compile_errors.txt
        fi
    fi
done

echo
echo -e "${YELLOW}3. Testing Swift compilation...${NC}"
echo "----------------------------------------"

SWIFT_FILES=(
    "Escrow Buddy/Mechanisms/EnhancedInvoke.swift"
    "Escrow Buddy/Mechanisms/EnhancedInvokeWithDaemon.swift"
)

for file in "${SWIFT_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -n "Testing $(basename "$file")... "
        if xcrun swiftc -parse -target x86_64-apple-macos10.15 \
                -import-objc-header "Escrow Buddy/Escrow Buddy-Bridging-Header.h" \
                "$file" 2>/tmp/compile_errors.txt; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌${NC}"
            echo "Errors:"
            head -5 /tmp/compile_errors.txt
        fi
    fi
done

echo
echo -e "${YELLOW}4. Checking for missing dependencies...${NC}"
echo "----------------------------------------"

# Check for required frameworks
FRAMEWORKS=("Foundation" "Security" "IOKit" "CoreServices")
for fw in "${FRAMEWORKS[@]}"; do
    if [ -d "/System/Library/Frameworks/$fw.framework" ]; then
        echo -e "${GREEN}✅${NC} $fw.framework"
    else
        echo -e "${RED}❌${NC} $fw.framework missing"
    fi
done

echo
echo -e "${YELLOW}5. Validating configuration files...${NC}"
echo "----------------------------------------"

# Check plists
PLISTS=(
    "LaunchDaemons/com.netflix.escrow-buddy.daemon.plist"
    "Configuration/EscrowBuddy-Enhanced-Profile.mobileconfig"
    "Escrow Buddy/Info.plist"
)

for plist in "${PLISTS[@]}"; do
    if [ -f "$plist" ]; then
        echo -n "Validating $(basename "$plist")... "
        if plutil -lint "$plist" >/dev/null 2>&1; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌ Invalid${NC}"
        fi
    fi
done

echo
echo "=== Test Complete ==="

# Summary
echo
echo -e "${GREEN}Ready to build with:${NC}"
echo "  make clean"
echo "  make release CODESIGN_IDENTITY=\"Developer ID Application: William Grzybowski (96KRXXRRDF)\""