#!/bin/bash

#
#  build_and_pkg_enhanced.sh
#  Escrow Buddy Enhanced
#
#  Copyright 2025 Escrow Buddy Enhanced
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

# Enhanced build script with support for new features
set -e

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="Escrow Buddy"
BUNDLE_IDENTIFIER="com.netflix.Escrow-Buddy"
CONFIGURATION="Release"
CODESIGN_IDENTITY="" # Set this to your Developer ID

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            CONFIGURATION="Debug"
            shift
            ;;
        --sign)
            CODESIGN_IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --debug          Build in Debug configuration"
            echo "  --sign ID        Code sign with specified identity"
            echo "  --notarize       Notarize the package (requires --sign)"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}=== Building Escrow Buddy Enhanced ===${NC}"

# Clean previous builds
echo -e "${YELLOW}Cleaning previous builds...${NC}"
cd "$PROJECT_ROOT/$PROJECT_NAME"
xcodebuild clean -project "$PROJECT_NAME.xcodeproj" -configuration "$CONFIGURATION" >/dev/null 2>&1

# Build the project
echo -e "${YELLOW}Building project in $CONFIGURATION configuration...${NC}"
xcodebuild -project "$PROJECT_NAME.xcodeproj" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    build analyze

# Get version from Info.plist
echo -e "${YELLOW}Determining version...${NC}"
INFO_PLIST="$PROJECT_ROOT/$PROJECT_NAME/build/Build/Products/$CONFIGURATION/$PROJECT_NAME.bundle/Contents/Info.plist"
VERSION=$(defaults read "$INFO_PLIST" CFBundleShortVersionString)
BUILD=$(defaults read "$INFO_PLIST" CFBundleVersion)
echo -e "${GREEN}  Version: $VERSION (Build $BUILD)${NC}"

# Prepare package directories
echo -e "${YELLOW}Preparing package structure...${NC}"
PKGROOT=$(mktemp -d /tmp/EscrowBuddy-Enhanced-root-XXXXXX)
OUTPUTDIR=$(mktemp -d /tmp/EscrowBuddy-Enhanced-output-XXXXXX)

# Create directory structure
mkdir -p "$PKGROOT/Library/Security/SecurityAgentPlugins"
mkdir -p "$PKGROOT/Library/Preferences"
mkdir -p "$PKGROOT/var/db"

# Copy the bundle
echo -e "${YELLOW}Copying bundle to package root...${NC}"
cp -R "$PROJECT_ROOT/$PROJECT_NAME/build/Build/Products/$CONFIGURATION/$PROJECT_NAME.bundle" \
    "$PKGROOT/Library/Security/SecurityAgentPlugins/"

# Create default configuration plist
echo -e "${YELLOW}Creating default configuration...${NC}"
cat > "$PKGROOT/Library/Preferences/com.netflix.Escrow-Buddy.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AutoRotationEnabled</key>
    <false/>
    <key>RotationIntervalDays</key>
    <integer>90</integer>
    <key>MaxKeyAge</key>
    <integer>365</integer>
    <key>RotateAfterUse</key>
    <false/>
    <key>ComplianceStandard</key>
    <string>none</string>
    <key>EnableComplianceReporting</key>
    <false/>
    <key>EnableNotifications</key>
    <true/>
    <key>NotificationDaysBefore</key>
    <integer>7</integer>
</dict>
</plist>
EOF

# Set proper permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chmod -R 755 "$PKGROOT/Library/Security/SecurityAgentPlugins/$PROJECT_NAME.bundle"
chmod 644 "$PKGROOT/Library/Preferences/com.netflix.Escrow-Buddy.plist"

# Code signing if identity provided
if [ -n "$CODESIGN_IDENTITY" ]; then
    echo -e "${YELLOW}Code signing bundle with identity: $CODESIGN_IDENTITY${NC}"
    codesign --force --deep --sign "$CODESIGN_IDENTITY" \
        --timestamp \
        --options runtime \
        "$PKGROOT/Library/Security/SecurityAgentPlugins/$PROJECT_NAME.bundle"
    
    # Verify code signature
    codesign --verify --deep --strict --verbose=2 \
        "$PKGROOT/Library/Security/SecurityAgentPlugins/$PROJECT_NAME.bundle"
fi

# Build the package
echo -e "${YELLOW}Building installer package...${NC}"
PACKAGE_NAME="EscrowBuddy-Enhanced-$VERSION.pkg"
OUTFILE="$OUTPUTDIR/$PACKAGE_NAME"

pkgbuild --root "$PKGROOT" \
    --identifier "$BUNDLE_IDENTIFIER" \
    --version "$VERSION" \
    --scripts "$SCRIPT_DIR/pkg" \
    --install-location / \
    "$OUTFILE"

# Sign the package if identity provided
if [ -n "$CODESIGN_IDENTITY" ]; then
    echo -e "${YELLOW}Signing installer package...${NC}"
    productsign --sign "$CODESIGN_IDENTITY" \
        --timestamp \
        "$OUTFILE" \
        "$OUTFILE.signed"
    mv "$OUTFILE.signed" "$OUTFILE"
fi

# Notarization if requested
if [ "$NOTARIZE" = true ] && [ -n "$CODESIGN_IDENTITY" ]; then
    echo -e "${YELLOW}Submitting package for notarization...${NC}"
    # Note: Requires xcrun notarytool configured with credentials
    xcrun notarytool submit "$OUTFILE" \
        --keychain-profile "AC_PASSWORD" \
        --wait
    
    echo -e "${YELLOW}Stapling notarization ticket...${NC}"
    xcrun stapler staple "$OUTFILE"
fi

# Create distribution archive
echo -e "${YELLOW}Creating distribution archive...${NC}"
DIST_DIR="$OUTPUTDIR/EscrowBuddy-Enhanced-$VERSION"
mkdir -p "$DIST_DIR"

# Copy package and documentation
cp "$OUTFILE" "$DIST_DIR/"
cp "$PROJECT_ROOT/README.md" "$DIST_DIR/"
cp "$PROJECT_ROOT/LICENSE" "$DIST_DIR/"

# Create configuration examples
mkdir -p "$DIST_DIR/Configuration Examples"
cat > "$DIST_DIR/Configuration Examples/MDM-Profile-Example.mobileconfig" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.netflix.Escrow-Buddy</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadIdentifier</key>
            <string>com.netflix.Escrow-Buddy.settings</string>
            <key>PayloadUUID</key>
            <string>$(uuidgen)</string>
            <key>PayloadDisplayName</key>
            <string>Escrow Buddy Enhanced Settings</string>
            <key>PayloadOrganization</key>
            <string>Your Organization</string>
            <key>AutoRotationEnabled</key>
            <true/>
            <key>RotationIntervalDays</key>
            <integer>90</integer>
            <key>ComplianceStandard</key>
            <string>NIST</string>
            <key>EnableComplianceReporting</key>
            <true/>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Escrow Buddy Enhanced Configuration</string>
    <key>PayloadIdentifier</key>
    <string>com.organization.escrowbuddy.enhanced</string>
    <key>PayloadOrganization</key>
    <string>Your Organization</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>$(uuidgen)</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
EOF

# Create deployment guide
cat > "$DIST_DIR/DEPLOYMENT.md" <<EOF
# Escrow Buddy Enhanced Deployment Guide

## Installation

1. Install the package: 
   \`\`\`
   sudo installer -pkg "EscrowBuddy-Enhanced-$VERSION.pkg" -target /
   \`\`\`

2. Configure settings via MDM profile or defaults:
   \`\`\`
   sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy AutoRotationEnabled -bool true
   sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy RotationIntervalDays -int 90
   \`\`\`

3. Verify installation:
   \`\`\`
   ls -la /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle
   \`\`\`

## Configuration Options

- **AutoRotationEnabled**: Enable automatic key rotation
- **RotationIntervalDays**: Days between automatic rotations
- **MaxKeyAge**: Maximum age before forced rotation
- **RotateAfterUse**: Rotate key after recovery usage
- **ComplianceStandard**: NIST, ISO27001, PCI-DSS, HIPAA, SOC2
- **EnableComplianceReporting**: Enable compliance reports

## Uninstallation

Run the uninstall script:
\`\`\`
sudo /usr/local/bin/uninstall_escrow_buddy.sh
\`\`\`
EOF

# Create ZIP archive
cd "$OUTPUTDIR"
zip -r "EscrowBuddy-Enhanced-$VERSION.zip" "EscrowBuddy-Enhanced-$VERSION" >/dev/null

# Cleanup temporary directories
echo -e "${YELLOW}Cleaning up temporary files...${NC}"
rm -rf "$PKGROOT"

# Summary
echo -e "${GREEN}=== Build Complete ===${NC}"
echo -e "${GREEN}Package: $OUTFILE${NC}"
echo -e "${GREEN}Archive: $OUTPUTDIR/EscrowBuddy-Enhanced-$VERSION.zip${NC}"
echo -e "${GREEN}Size: $(du -h "$OUTFILE" | cut -f1)${NC}"

# Checksum
echo -e "${YELLOW}SHA256 Checksum:${NC}"
shasum -a 256 "$OUTFILE" | cut -d' ' -f1

echo -e "${GREEN}Build successful!${NC}"