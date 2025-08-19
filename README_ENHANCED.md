# Escrow Buddy Enhanced

<p align="center">
  <img src="images/escrow_buddy_logo_600px.png" alt="Escrow Buddy Enhanced Logo" width="300">
</p>

## Enterprise-Grade FileVault Recovery Key Management

> **Attribution**: Escrow Buddy Enhanced is an enhanced fork of [Escrow Buddy](https://github.com/macadmins/escrow-buddy) created by Netflix Client Systems Engineering. See [CREDITS.md](CREDITS.md) for full acknowledgments.

Escrow Buddy Enhanced extends the original [Netflix Escrow Buddy](https://github.com/macadmins/escrow-buddy) with automatic key rotation, compliance reporting, and enterprise integration capabilities.

## 🚀 Key Features

### Core Functionality
- ✅ **Automatic Key Rotation** - Schedule-based and policy-driven rotation
- ✅ **Compliance Reporting** - NIST, ISO27001, PCI-DSS, HIPAA, SOC2 support
- ✅ **MDM Integration** - Full Jamf Pro API integration
- ✅ **Smart Rotation Triggers** - Age-based, usage-based, compliance-driven
- ✅ **Comprehensive Logging** - JSON, structured, and audit trail logging
- ✅ **Zero-Touch Deployment** - MDM profile-based configuration

### Enhanced Capabilities
- 📊 Real-time compliance scoring and violation tracking
- 🔔 Pre-expiration notifications and alerts
- 📈 Historical tracking and trend analysis
- 🔄 Webhook integration for external systems
- 📝 Multiple report formats (JSON, XML, CSV, HTML)
- 🔐 Secure key lifecycle management

## 📋 Requirements

- macOS 10.15 (Catalina) or later
- FileVault 2 enabled
- MDM with FileVault recovery key escrow configured
- Jamf Pro 10.0+ (optional, for API features)

## 🛠 Installation

### Quick Install

```bash
# Download and install the latest release
curl -LO https://github.com/your-org/escrow-buddy-enhanced/releases/latest/download/EscrowBuddy-Enhanced.pkg
sudo installer -pkg EscrowBuddy-Enhanced.pkg -target /
```

### Build from Source

```bash
# Clone the repository
git clone https://github.com/your-org/escrow-buddy-enhanced.git
cd escrow-buddy-enhanced

# Build and package
make all

# Install
sudo make install
```

## ⚙️ Configuration

### Basic Setup

Enable auto-rotation with default settings:

```bash
sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy AutoRotationEnabled -bool true
```

### MDM Configuration Profile

Deploy the included configuration profile for centralized management:

```xml
<key>AutoRotationEnabled</key>
<true/>
<key>RotationIntervalDays</key>
<integer>90</integer>
<key>ComplianceStandard</key>
<string>NIST</string>
```

See `Configuration/EscrowBuddy-Enhanced-Profile.mobileconfig` for a complete template.

## 🔄 Rotation Policies

### Automatic Triggers

| Trigger | Description | Configuration |
|---------|-------------|---------------|
| **Age-Based** | Rotate after X days | `RotationIntervalDays` |
| **Usage-Based** | Rotate after recovery | `RotateAfterUse` |
| **Compliance** | Meet regulatory requirements | `ComplianceStandard` |
| **Manual** | Admin-initiated rotation | `GenerateNewKey` flag |

### Compliance Standards

| Standard | Max Key Age | Requirements |
|----------|-------------|--------------|
| **NIST 800-171** | 90 days | Escrow verification, audit logging |
| **ISO 27001** | 180 days | Average lifetime tracking |
| **PCI-DSS 4.0** | 90 days | Mandatory verification |
| **HIPAA** | 90 days | Audit trail required |
| **SOC 2** | 365 days | Control tracking |

## 📊 Monitoring & Reporting

### Log Locations

- Main log: `/var/log/escrow-buddy.log`
- Audit trail: `/var/log/escrow-buddy-audit.log`
- Compliance reports: `/var/db/escrow_buddy_compliance/`

### Viewing Status

```bash
# Check current configuration
defaults read /Library/Preferences/com.netflix.Escrow-Buddy

# View recent rotation events
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1h

# Generate compliance report
/usr/local/bin/escrow-buddy-report --format json --standard NIST
```

## 🔌 Jamf Pro Integration

### Setup

1. Create API user with Computer read/update permissions
2. Configure connection:
   ```bash
   sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy EnableAPIIntegration -bool true
   sudo defaults write /Library/Preferences/com.netflix.Escrow-Buddy JamfServerURL -string "https://your.jamf.server"
   ```

3. Create Extension Attributes:
   - `FileVault_Key_Rotation_Status`
   - `FileVault_Compliance_Status`

### Smart Groups

Create dynamic groups for automated management:
- **Keys Needing Rotation**: Key age > 75 days
- **Non-Compliant Devices**: Compliance status != "Compliant"
- **Recently Rotated**: Last rotation < 7 days

## 🏗 Architecture

```
┌─────────────────────────────────────┐
│     macOS Authorization Plugin      │
├─────────────────────────────────────┤
│         Enhanced Components         │
├──────────────┬──────────────────────┤
│ RotationMgr  │  ConfigurationMgr    │
├──────────────┼──────────────────────┤
│ LifecycleTrk │  ComplianceReporter  │
├──────────────┼──────────────────────┤
│ JamfAPIClient│  EnhancedLogger      │
└──────────────┴──────────────────────┘
```

## 🛡 Security Considerations

- Recovery keys are **never** stored locally
- All key operations require admin privileges
- Audit trail for all rotation events
- Secure storage for metadata only
- API credentials use OAuth/tokens only

## 🔧 Troubleshooting

### Common Issues

**Plugin not loading**
```bash
sudo /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle/Contents/Resources/AuthDBSetup.sh
```

**Rotation not triggering**
```bash
# Check key age
sudo plutil -p /var/db/escrow_buddy_lifecycle.plist

# Verify configuration
defaults read /Library/Preferences/com.netflix.Escrow-Buddy
```

**API connection failures**
```bash
# Test connectivity
curl -I https://your.jamf.server/JSSResource/computers

# Check API permissions in Jamf Pro
```

## 📚 Documentation

- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Detailed installation and configuration
- [API Reference](docs/API_REFERENCE.md) - Jamf API integration details
- [Compliance Guide](docs/COMPLIANCE_GUIDE.md) - Standards and reporting
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Based on original [Escrow Buddy](https://github.com/macadmins/escrow-buddy) by Netflix
- macOS admin community for testing and feedback
- Contributors and maintainers

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/your-org/escrow-buddy-enhanced/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/escrow-buddy-enhanced/discussions)
- **Security**: Report vulnerabilities via [Security Policy](SECURITY.md)

## 🚦 Project Status

![Build Status](https://img.shields.io/github/workflow/status/your-org/escrow-buddy-enhanced/CI)
![Version](https://img.shields.io/github/v/release/your-org/escrow-buddy-enhanced)
![License](https://img.shields.io/github/license/your-org/escrow-buddy-enhanced)
![macOS Support](https://img.shields.io/badge/macOS-10.15%2B-blue)

---

**Escrow Buddy Enhanced** - Enterprise FileVault Key Management Made Simple