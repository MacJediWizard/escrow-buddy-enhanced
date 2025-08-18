# Escrow Buddy Enhanced - Deployment Guide

## Overview

Escrow Buddy Enhanced extends the original Netflix Escrow Buddy with automatic FileVault recovery key rotation, compliance reporting, and enterprise integration capabilities.

## System Requirements

- macOS 10.15 (Catalina) or later
- FileVault 2 enabled
- MDM enrollment (recommended)
- Jamf Pro 10.0+ (optional, for API integration)

## Installation Methods

### Method 1: Package Installation

1. **Download the installer package**
   ```bash
   # Download the latest release
   curl -LO https://github.com/your-org/escrow-buddy-enhanced/releases/latest/download/EscrowBuddy-Enhanced.pkg
   ```

2. **Install the package**
   ```bash
   sudo installer -pkg EscrowBuddy-Enhanced.pkg -target /
   ```

3. **Verify installation**
   ```bash
   ls -la /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle
   defaults read /Library/Preferences/com.netflix.Escrow-Buddy
   ```

### Method 2: MDM Deployment (Recommended)

1. **Upload package to MDM**
   - Add EscrowBuddy-Enhanced.pkg to your MDM's package repository
   - Create a policy to deploy the package

2. **Deploy configuration profile**
   - Upload `Configuration/EscrowBuddy-Enhanced-Profile.mobileconfig`
   - Scope to target computers
   - Deploy before or with the package

3. **Trigger installation**
   - Deploy via policy or Self Service
   - Package will auto-configure based on profile settings

## Configuration

### Basic Configuration (Manual)

```bash
# Enable auto-rotation
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy AutoRotationEnabled -bool true

# Set rotation interval (days)
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy RotationIntervalDays -int 90

# Set compliance standard
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy ComplianceStandard -string "NIST"

# Enable compliance reporting
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy EnableComplianceReporting -bool true
```

### Advanced Configuration Options

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `AutoRotationEnabled` | Boolean | false | Enable automatic key rotation |
| `RotationIntervalDays` | Integer | 90 | Days between automatic rotations |
| `RotateAfterUse` | Boolean | false | Rotate key after recovery usage |
| `MaxKeyAge` | Integer | 365 | Maximum key age in days |
| `MinimumKeyAge` | Integer | 1 | Minimum age before rotation allowed |
| `ComplianceStandard` | String | "none" | Compliance standard (NIST, ISO27001, PCI-DSS, HIPAA, SOC2) |
| `EnableComplianceReporting` | Boolean | false | Generate compliance reports |
| `EnableNotifications` | Boolean | true | Show rotation notifications |
| `NotificationDaysBefore` | Integer | 7 | Days before expiry to notify |
| `EnableAPIIntegration` | Boolean | false | Enable Jamf Pro API integration |
| `JamfServerURL` | String | "" | Jamf Pro server URL |
| `EnableWebhooks` | Boolean | false | Enable webhook notifications |
| `WebhookURL` | String | "" | Webhook endpoint URL |

## Compliance Standards

### NIST 800-171
- Maximum key age: 90 days
- Requires key escrow verification
- Audit logging enabled

### ISO 27001:2013
- Maximum key age: 180 days
- Average key lifetime tracking
- Escrow verification required

### PCI-DSS 4.0
- Maximum key age: 90 days
- Mandatory escrow verification
- Key complexity enforcement

### HIPAA Security Rule
- Maximum key age: 90 days
- Audit trail required
- Escrow verification mandatory

### SOC 2 Type II
- Maximum key age: 365 days
- Control implementation tracking
- Compliance reporting required

## Jamf Pro Integration

### Prerequisites
1. Jamf Pro 10.0 or later
2. API user with appropriate permissions
3. Computer record read/update permissions

### Configuration
```bash
# Enable API integration
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy EnableAPIIntegration -bool true

# Set Jamf server URL
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy JamfServerURL -string "https://your.jamf.server"
```

### Extension Attributes
Create these extension attributes in Jamf Pro:

1. **FileVault Key Rotation Status**
   - Data Type: String
   - Input Type: Text Field

2. **FileVault Compliance Status**
   - Data Type: String
   - Input Type: Text Field

### Smart Groups
Create smart groups for rotation management:

1. **Keys Needing Rotation**
   - Criteria: Key age > 75 days

2. **Non-Compliant Devices**
   - Criteria: Compliance status != "Compliant"

## Monitoring and Reporting

### Log Files
- Main log: `/var/log/escrow-buddy.log`
- Audit log: `/var/log/escrow-buddy-audit.log`
- Installation log: `/var/log/escrow-buddy-install.log`

### Viewing Logs
```bash
# View recent rotation events
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1h

# View compliance reports
cat /var/db/escrow_buddy_compliance/report_*.json
```

### Compliance Reports
Reports are generated in `/var/db/escrow_buddy_compliance/` in these formats:
- JSON (default)
- XML
- CSV
- HTML

## Troubleshooting

### Common Issues

1. **Plugin not loading**
   ```bash
   # Verify authorization database
   sudo security authorizationdb read system.login.console
   
   # Re-run setup
   sudo /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle/Contents/Resources/AuthDBSetup.sh
   ```

2. **Rotation not triggering**
   ```bash
   # Check configuration
   defaults read /Library/Preferences/com.netflix.Escrow-Buddy
   
   # Verify key age
   sudo cat /var/db/escrow_buddy_lifecycle.plist
   ```

3. **API connection failures**
   ```bash
   # Test Jamf connection
   curl -I https://your.jamf.server/JSSResource/computers
   
   # Check API permissions
   # Verify user has Computer Objects read/update
   ```

### Debug Mode
Enable debug logging:
```bash
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy DebugMode -bool true
```

## Uninstallation

### Complete Removal
```bash
sudo /usr/local/bin/uninstall_escrow_buddy.sh
```

### Manual Removal
```bash
# Remove from authorization database
sudo /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle/Contents/Resources/AuthDBTeardown.sh

# Remove bundle
sudo rm -rf /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle

# Remove preferences (optional)
sudo rm -f /Library/Preferences/com.netflix.Escrow-Buddy.plist

# Remove database files (optional)
sudo rm -f /var/db/escrow_buddy_*.plist

# Remove logs
sudo rm -f /var/log/escrow-buddy*.log
```

## Security Considerations

1. **Permissions**: All configuration files should be owned by root:wheel with 644 permissions
2. **Key Storage**: Recovery keys are never stored locally, only metadata
3. **API Credentials**: Use OAuth tokens or API tokens, never store passwords
4. **Audit Trail**: All rotation events are logged for compliance
5. **Escrow Verification**: Keys are verified with MDM after generation

## Support

For issues or questions:
1. Check the [GitHub Issues](https://github.com/your-org/escrow-buddy-enhanced/issues)
2. Review logs in `/var/log/escrow-buddy.log`
3. Contact your MDM administrator

## License

Licensed under the Apache License, Version 2.0. See LICENSE file for details.