# Escrow Buddy Enhanced

<p align="center">
  <img src="../logo.png" alt="Escrow Buddy Enhanced Logo" width="400">
</p>

> **Enterprise-grade FileVault key rotation without user disruption**

Escrow Buddy Enhanced is an enhanced version of Netflix's original Escrow Buddy that adds automatic background rotation capabilities, eliminating the need for users to logout for key rotation.

## 🚀 What's New in Enhanced Version

| Feature | Original Escrow Buddy | Escrow Buddy Enhanced |
|---------|----------------------|----------------------|
| **Key Rotation** | Requires user logout | Automatic background rotation |
| **Scheduling** | Manual trigger only | Automated scheduling (configurable) |
| **Compliance** | Basic logging | Full compliance reporting (NIST, ISO27001, PCI-DSS, HIPAA, SOC2) |
| **MDM Integration** | Basic escrow | Full API integration with Jamf Pro |
| **Architecture** | Auth plugin only | Auth plugin + background daemon |
| **Credential Handling** | N/A | MDM-based (no credential storage) |
| **Monitoring** | Limited | Comprehensive logging and metrics |

## 📋 Requirements

- macOS 10.15 (Catalina) or later
- MDM solution (Jamf Pro, SimpleMDM, Workspace ONE, etc.)
- FileVault enabled
- FDERecoveryKeyEscrow profile deployed
- Apple Developer ID for code signing (recommended)

## 🏗️ Architecture

```
MDM Server → Configuration & Commands
    ↓
EscrowBuddyDaemon (Background Service)
    ↓ XPC Communication
EBAuthPlugin (Login/Logout Hook)
    ↓
FileVault Key Rotation
```

## 📦 Quick Start

### 1. Build from Source

```bash
# Clone repository
git clone https://github.com/yourusername/escrow-buddy-enhanced.git
cd escrow-buddy-enhanced

# Add files to Xcode project
./add_files_to_xcode.sh
open "Escrow Buddy.xcodeproj"  # Note: Xcode project retains original name for compatibility
# Manually add files as instructed

# Build
make release CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

### 2. Deploy via MDM

**Jamf Pro:**
1. Upload package to Jamf Admin
2. Create configuration profile with settings
3. Create policy for deployment
4. Scope to test group, then production

**Generic MDM:**
```bash
# Deploy package
installer -pkg EscrowBuddyEnhanced.pkg -target /

# Configure
defaults write /Library/Preferences/com.netflix.escrow-buddy AutoRotationEnabled -bool YES
defaults write /Library/Preferences/com.netflix.escrow-buddy RotationIntervalDays -int 90
```

### 3. Verify Installation

```bash
# Check daemon status
sudo launchctl list | grep escrow-buddy

# View logs
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1h

# Check rotation status
sudo /usr/local/bin/EscrowBuddyDaemon --status
```

## ⚙️ Configuration

### Basic Configuration (MDM Profile)

```xml
<dict>
    <key>AutoRotationEnabled</key>
    <true/>
    <key>RotationIntervalDays</key>
    <integer>90</integer>
    <key>MDMRotationMethod</key>
    <string>JamfPro</string>
    <key>JamfServerURL</key>
    <string>https://your.jamf.server:8443</string>
    <key>ComplianceStandard</key>
    <string>NIST</string>
</dict>
```

### Rotation Methods

1. **Jamf Pro** (Recommended for Jamf environments)
2. **Apple MDM** (Generic MDM commands)
3. **Profile-based** (Configuration profile triggers)
4. **Custom Script** (Fallback method)

## 🔧 Usage

### Automatic Operation

Once installed, Escrow Buddy Enhanced operates automatically:
- Checks key age based on configured interval
- Rotates keys when needed
- Reports compliance status
- No user interaction required

### Manual Operations

```bash
# Force immediate rotation
sudo kill -USR1 $(pgrep EscrowBuddyDaemon)

# Reload configuration
sudo kill -HUP $(pgrep EscrowBuddyDaemon)

# Check status
sudo /usr/local/bin/EscrowBuddyDaemon --status

# Generate compliance report
sudo /usr/local/bin/EscrowBuddyDaemon --report
```

## 📊 Monitoring

### View Logs
```bash
# Real-time logs
log stream --predicate 'subsystem == "com.netflix.Escrow-Buddy"'

# Historical logs
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1d

# Error logs only
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND level == "ERROR"' --last 1d
```

### Check Compliance
```bash
# View latest compliance report
cat /var/log/escrow_buddy_compliance/latest.json | jq

# Check rotation history
sudo plutil -p /var/db/escrow_buddy_keys.plist
```

## 🔒 Security

### Key Security Features

- **No User Credentials Stored** - All operations via MDM
- **Encrypted Communication** - TLS for all API calls
- **Code Signing** - Support for notarization
- **Audit Trail** - Complete logging of all operations
- **Least Privilege** - Daemon runs with minimal permissions

### Best Practices

1. Always deploy via MDM with signed packages
2. Use configuration profiles (not local preferences)
3. Enable compliance reporting
4. Monitor logs regularly
5. Test in non-production first

## 🛠️ Troubleshooting

### Common Issues

**Daemon not running:**
```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

**Rotation failing:**
```bash
# Check MDM connection
sudo /usr/local/bin/EscrowBuddyDaemon --test-mdm

# Check FileVault status
fdesetup status
```

**XPC errors:**
```bash
# Restart daemon
sudo launchctl bootout system/com.netflix.escrow-buddy.daemon
sudo launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

See [TROUBLESHOOTING.md](Documentation/TROUBLESHOOTING.md) for comprehensive guide.

## 📚 Documentation

- **[Deployment Guide](Documentation/DEPLOYMENT_GUIDE.md)** - Step-by-step deployment instructions
- **[Administrator Manual](Documentation/ADMINISTRATOR_MANUAL.md)** - Comprehensive admin guide
- **[Troubleshooting Guide](Documentation/TROUBLESHOOTING.md)** - Problem resolution
- **[Implementation Summary](IMPLEMENTATION_SUMMARY.md)** - Technical implementation details

## 🏢 Enterprise Features

### Compliance Reporting
- NIST 800-171 (90-day rotation)
- ISO 27001 (Key management)
- PCI-DSS (Cryptographic requirements)
- HIPAA (Technical safeguards)
- SOC 2 (Security controls)

### Integration Capabilities
- Jamf Pro API
- Splunk/SIEM
- ServiceNow
- Custom webhooks

### Scalability
- Supports thousands of endpoints
- Staggered rotation to prevent overload
- Configurable retry logic
- Batch processing

## 📈 Metrics and KPIs

Monitor these metrics for success:
- **Rotation Success Rate**: Target >95%
- **Average Key Age**: Target <90 days
- **Compliance Score**: Target 100%
- **Failed Rotations**: Target <5%
- **User Impact**: Target 0

## 🔄 Migration from Original Escrow Buddy

1. Original Escrow Buddy continues to work
2. Install Enhanced version alongside
3. Enhanced daemon takes over rotation
4. No user disruption during migration

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new features
4. Submit a pull request

## 📄 License

Apache License 2.0 - Same as original Escrow Buddy

## 🙏 Credits

- Original [Escrow Buddy](https://github.com/macadmins/escrow-buddy) by Netflix
- Enhanced version adds enterprise features while maintaining compatibility

## ⚡ Quick Reference

```bash
# Essential Commands
sudo launchctl list | grep escrow-buddy           # Check status
sudo kill -USR1 $(pgrep EscrowBuddyDaemon)       # Force rotation
sudo kill -HUP $(pgrep EscrowBuddyDaemon)        # Reload config
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1h  # View logs

# File Locations
/usr/local/bin/EscrowBuddyDaemon                 # Daemon binary
/Library/Preferences/com.netflix.escrow-buddy.plist  # Configuration
/var/db/escrow_buddy_keys.plist                  # Key history
/var/log/escrow_buddy_compliance/                # Compliance reports
```

## 🚨 Support

For issues:
1. Check [Troubleshooting Guide](Documentation/TROUBLESHOOTING.md)
2. Review logs for errors
3. Search existing GitHub issues
4. Create new issue with diagnostic data

---

**Ready for enterprise deployment** ✅