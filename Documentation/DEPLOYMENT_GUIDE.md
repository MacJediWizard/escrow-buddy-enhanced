# Escrow Buddy Enhanced - Deployment Guide

## Table of Contents
1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [Building from Source](#building-from-source)
3. [Deployment Methods](#deployment-methods)
4. [MDM Configuration](#mdm-configuration)
5. [Testing](#testing)
6. [Production Rollout](#production-rollout)
7. [Verification](#verification)

## Pre-Deployment Checklist

### Requirements
- [ ] macOS 10.15 or later on target machines
- [ ] MDM solution deployed (Jamf Pro, SimpleMDM, etc.)
- [ ] FileVault enabled on target machines
- [ ] FDERecoveryKeyEscrow profile deployed
- [ ] Admin/root privileges for installation
- [ ] Apple Developer ID for code signing (recommended)

### Infrastructure
- [ ] MDM server configured and accessible
- [ ] Test environment available
- [ ] Logging/monitoring system ready
- [ ] Backup of current FileVault keys (if available)

## Building from Source

### Step 1: Clone and Prepare

```bash
# Clone the repository
git clone https://github.com/yourusername/escrow-buddy-enhanced.git
cd escrow-buddy-enhanced

# Verify all files are present
./final_verification.sh
```

### Step 2: Add Files to Xcode Project

```bash
# Run the helper script
./add_files_to_xcode.sh

# Open Xcode
open "Escrow Buddy.xcodeproj"
```

In Xcode:
1. Right-click "Escrow Buddy" group
2. Select "Add Files to Escrow Buddy..."
3. Add all new .h and .m files from the list
4. Create "EscrowBuddyDaemon" group and add daemon files
5. Ensure Swift files are added to the main target

### Step 3: Build

```bash
# Debug build for testing
make debug

# Release build with code signing
make release CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"

# Verify the build
codesign -dvv build/Release/Escrow\ Buddy.bundle
codesign -dvv build/Release/EscrowBuddyDaemon
```

### Step 4: Create Installer Package

```bash
# Create the package
make package

# Sign the package (optional but recommended)
productsign --sign "Developer ID Installer: Your Name (TEAMID)" \
    EscrowBuddyEnhanced-unsigned.pkg \
    EscrowBuddyEnhanced.pkg

# Notarize (recommended for macOS 10.15+)
xcrun altool --notarize-app \
    --primary-bundle-id "com.netflix.escrow-buddy" \
    --username "your@email.com" \
    --password "@keychain:altool" \
    --file EscrowBuddyEnhanced.pkg
```

## Deployment Methods

### Method 1: Jamf Pro Deployment

#### 1. Upload Package
1. Navigate to **Settings > Computer Management > Packages**
2. Click **New**
3. Upload `EscrowBuddyEnhanced.pkg`
4. Set priority to **10**

#### 2. Create Configuration Profile
1. Navigate to **Computers > Configuration Profiles**
2. Click **New**
3. Add **Custom Settings** payload:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.netflix.escrow-buddy</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadIdentifier</key>
            <string>com.netflix.escrow-buddy.config</string>
            <key>PayloadUUID</key>
            <string>YOUR-UUID-HERE</string>
            <key>PayloadDisplayName</key>
            <string>Escrow Buddy Enhanced Configuration</string>
            <key>AutoRotationEnabled</key>
            <true/>
            <key>RotationIntervalDays</key>
            <integer>90</integer>
            <key>MDMRotationMethod</key>
            <string>JamfPro</string>
            <key>JamfServerURL</key>
            <string>https://your.jamf.server:8443</string>
            <key>EnableComplianceReporting</key>
            <true/>
            <key>ComplianceStandard</key>
            <string>NIST</string>
        </dict>
    </array>
</dict>
</plist>
```

#### 3. Create Policy
1. Navigate to **Computers > Policies**
2. Click **New**
3. Configure:
   - **General:**
     - Display Name: "Install Escrow Buddy Enhanced"
     - Trigger: Recurring Check-in
     - Frequency: Once per computer
   - **Packages:**
     - Add `EscrowBuddyEnhanced.pkg`
   - **Scripts:**
     - Add post-install script (see below)
   - **Scope:**
     - Target: All Managed Clients (or test group first)

#### 4. Post-Install Script
```bash
#!/bin/bash

# Configure authorization database
/usr/local/bin/escrow-buddy-setup.sh

# Start the daemon
launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist

# Trigger initial check
kill -USR1 $(pgrep EscrowBuddyDaemon) 2>/dev/null || true

echo "Escrow Buddy Enhanced installed successfully"
exit 0
```

#### 5. Create Smart Groups
- **Keys Need Rotation:**
  ```
  Criteria: Extension Attribute "FileVault Key Age" > 90 days
  ```
- **Missing Recovery Keys:**
  ```
  Criteria: FileVault Recovery Key Validation = Not Valid
  ```

### Method 2: Generic MDM Deployment

#### 1. Package Distribution
Upload `EscrowBuddyEnhanced.pkg` to your MDM's package repository.

#### 2. Configuration Profile
Deploy configuration profile with custom settings:

```bash
# Generate UUID
uuidgen

# Create the profile using your MDM's interface
# Include the PayloadContent from above
```

#### 3. Installation Command
```bash
#!/bin/bash
# Run as root via MDM

# Install the package
installer -pkg /path/to/EscrowBuddyEnhanced.pkg -target /

# Configure
defaults write /Library/Preferences/com.netflix.escrow-buddy AutoRotationEnabled -bool YES
defaults write /Library/Preferences/com.netflix.escrow-buddy RotationIntervalDays -int 90
defaults write /Library/Preferences/com.netflix.escrow-buddy MDMRotationMethod -string "AppleMDM"

# Start daemon
launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

### Method 3: Manual Deployment (Testing Only)

```bash
# Copy files
sudo cp -R build/Release/Escrow\ Buddy.bundle /Library/Security/SecurityAgentPlugins/
sudo cp build/Release/EscrowBuddyDaemon /usr/local/bin/
sudo cp LaunchDaemons/com.netflix.escrow-buddy.daemon.plist /Library/LaunchDaemons/
sudo cp Scripts/escrow_buddy_rotate.sh /usr/local/bin/

# Set permissions
sudo chmod 755 /usr/local/bin/EscrowBuddyDaemon
sudo chmod 755 /usr/local/bin/escrow_buddy_rotate.sh
sudo chmod 644 /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist

# Configure authorization database
sudo sqlite3 /var/db/auth.db <<EOF
INSERT OR REPLACE INTO mechanisms (plugin, mechanism, privileged, entry) 
VALUES ('Escrow Buddy', 'EnhancedInvokeWithDaemon', 1, 'system.login.console');
EOF

# Start daemon
sudo launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

## MDM Configuration

### Jamf Pro API Setup

1. **Create API User:**
   - Username: `escrow_buddy_api`
   - Access Level: Full Access (or custom with required permissions)
   - Privileges needed:
     - Read/Update Computers
     - Read Computer Extension Attributes
     - Create/Read/Update Policies

2. **Store Credentials Securely:**
```bash
# Store in keychain
security add-generic-password \
    -a "escrow_buddy_api" \
    -s "com.netflix.escrow-buddy.jamf" \
    -w "your-api-password"
```

3. **Configure in Profile:**
```xml
<key>JamfAPIUsername</key>
<string>escrow_buddy_api</string>
<key>JamfAPIKeychain</key>
<string>com.netflix.escrow-buddy.jamf</string>
```

### Rotation Methods Configuration

#### Method 1: Jamf Pro API
```xml
<key>MDMRotationMethod</key>
<string>JamfPro</string>
<key>JamfServerURL</key>
<string>https://your.jamf.server:8443</string>
```

#### Method 2: Apple MDM
```xml
<key>MDMRotationMethod</key>
<string>AppleMDM</string>
<key>MDMServerURL</key>
<string>https://your.mdm.server</string>
```

#### Method 3: Profile-Based
```xml
<key>MDMRotationMethod</key>
<string>Profile</string>
<key>RotationProfileIdentifier</key>
<string>com.company.filevault.rotation</string>
```

#### Method 4: Custom Script
```xml
<key>MDMRotationMethod</key>
<string>Script</string>
<key>RotationScriptPath</key>
<string>/usr/local/bin/escrow_buddy_rotate.sh</string>
```

## Testing

### Test Environment Setup

1. **Create Test Group:**
   - 5-10 test machines
   - Various macOS versions
   - Different FileVault states

2. **Deploy to Test Group:**
```bash
# Scope policy to test group only
# Monitor for 24-48 hours
```

3. **Verification Tests:**

```bash
# Check daemon status
sudo launchctl print system/com.netflix.escrow-buddy.daemon

# Verify XPC connection
sudo /usr/local/bin/EscrowBuddyDaemon --status

# Check logs
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1h

# Trigger test rotation
sudo kill -USR1 $(pgrep EscrowBuddyDaemon)

# Verify key age
sudo plutil -p /var/db/escrow_buddy_keys.plist
```

### Success Criteria

- [ ] Daemon starts automatically on boot
- [ ] No errors in system logs
- [ ] Keys rotate on schedule
- [ ] New keys escrow to MDM
- [ ] Compliance reports generate
- [ ] No user disruption during rotation

## Production Rollout

### Phased Deployment

#### Phase 1: Pilot (Week 1)
- Deploy to IT team machines
- Monitor closely
- Document any issues

#### Phase 2: Limited (Week 2-3)
- Deploy to 10% of fleet
- Monitor logs and metrics
- Gather feedback

#### Phase 3: Broad (Week 4-5)
- Deploy to 50% of fleet
- Continue monitoring
- Prepare for full deployment

#### Phase 4: Full (Week 6)
- Deploy to all machines
- Monitor for edge cases

### Monitoring During Rollout

```bash
# Create monitoring script
#!/bin/bash

# Check for failures
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND level == "ERROR"' --last 1d

# Count successful rotations
grep "Rotation completed successfully" /var/log/escrow_buddy_daemon.log | wc -l

# Check compliance status
ls -la /var/log/escrow_buddy_compliance/*.json | wc -l
```

### Rollback Plan

If issues occur:

```bash
#!/bin/bash
# Emergency rollback script

# Stop daemon
sudo launchctl bootout system/com.netflix.escrow-buddy.daemon

# Remove enhanced components
sudo rm /usr/local/bin/EscrowBuddyDaemon
sudo rm /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist

# Keep original Escrow Buddy functional
echo "Rollback complete - original Escrow Buddy remains"
```

## Verification

### Post-Deployment Checks

1. **Verify Installation:**
```bash
# Check all components
ls -la /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle
ls -la /usr/local/bin/EscrowBuddyDaemon
ls -la /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

2. **Verify Operation:**
```bash
# Check daemon is running
ps aux | grep EscrowBuddyDaemon

# Check last rotation
sudo cat /var/db/escrow_buddy_daemon_status.plist

# Verify MDM escrow
# Check in your MDM console for updated recovery keys
```

3. **Generate Reports:**
```bash
# Compliance report
sudo /usr/local/bin/EscrowBuddyDaemon --report

# Statistics
sudo /usr/local/bin/EscrowBuddyDaemon --stats
```

### Success Metrics

Monitor these KPIs:
- **Rotation Success Rate:** Target > 95%
- **Average Key Age:** Target < 90 days
- **Compliance Score:** Target 100%
- **Failed Rotations:** Target < 5%
- **User Complaints:** Target 0

### MDM Dashboard

Create dashboard to monitor:
- Devices with keys > 90 days old
- Recent rotation failures
- Compliance status by department
- Rotation timeline/history

## Next Steps

After successful deployment:
1. Review TROUBLESHOOTING.md for common issues
2. Set up automated monitoring
3. Schedule regular compliance audits
4. Plan for macOS version updates
5. Document organization-specific procedures