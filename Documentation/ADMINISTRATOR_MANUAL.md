# Escrow Buddy Enhanced - Administrator Manual

## Executive Summary

Escrow Buddy Enhanced is an enterprise-grade FileVault recovery key management solution that automatically rotates encryption keys without requiring user logout. This manual provides comprehensive guidance for system administrators managing the deployment, configuration, and maintenance of this solution.

### Key Benefits
- **Zero User Disruption** - Keys rotate automatically in background
- **No Credential Storage** - Uses MDM commands exclusively
- **Compliance Ready** - Built-in reporting for NIST, ISO27001, PCI-DSS, HIPAA, SOC2
- **Enterprise Scale** - Supports thousands of endpoints
- **Audit Trail** - Complete logging of all operations

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Configuration Management](#configuration-management)
3. [Daily Operations](#daily-operations)
4. [Monitoring and Reporting](#monitoring-and-reporting)
5. [Security Best Practices](#security-best-practices)
6. [Compliance Management](#compliance-management)
7. [Performance Tuning](#performance-tuning)
8. [Backup and Recovery](#backup-and-recovery)
9. [Integration Guide](#integration-guide)
10. [Reference](#reference)

## Architecture Overview

### System Components

```
┌──────────────────────────────────────────────────────┐
│                    MDM Server                        │
│         (Jamf Pro / SimpleMDM / Workspace ONE)       │
└────────────────────┬─────────────────────────────────┘
                     │ Configuration Profiles
                     │ MDM Commands
                     │ API Calls
                     ▼
┌──────────────────────────────────────────────────────┐
│              Mac Endpoint                            │
│  ┌────────────────────────────────────────────────┐  │
│  │         EscrowBuddyDaemon (root)              │  │
│  │  • LaunchDaemon service                       │  │
│  │  • MDMRotationHandler                         │  │
│  │  • ComplianceReporter                         │  │
│  │  • XPC Service Provider                       │  │
│  └────────────────────┬──────────────────────────┘  │
│                       │ XPC                          │
│  ┌────────────────────▼──────────────────────────┐  │
│  │    EBAuthPlugin (user context)                │  │
│  │  • Authorization mechanism                    │  │
│  │  • Login/logout hooks                         │  │
│  │  • XPC Client                                 │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### Data Flow

1. **Configuration** → MDM deploys profile → Daemon reads configuration
2. **Scheduling** → Daemon checks rotation schedule → Determines if rotation needed
3. **Rotation** → Daemon triggers MDM rotation → MDM sends commands → FileVault rotates key
4. **Escrow** → New key generated → Key escrowed to MDM → Verification performed
5. **Reporting** → Compliance report generated → Sent to logging system

## Configuration Management

### Configuration Hierarchy

Configuration is read in the following order (later overrides earlier):

1. **Defaults** (built into binary)
2. **Local Preferences** (/Library/Preferences/com.netflix.escrow-buddy.plist)
3. **MDM Profile** (/Library/Managed Preferences/com.netflix.escrow-buddy.plist)
4. **Runtime Overrides** (command-line arguments)

### Core Configuration Options

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Rotation Settings -->
    <key>AutoRotationEnabled</key>
    <true/>
    <key>RotationIntervalDays</key>
    <integer>90</integer>
    <key>MaxKeyAge</key>
    <integer>365</integer>
    <key>ForceRotationOnHighRiskEvents</key>
    <true/>
    
    <!-- MDM Configuration -->
    <key>MDMRotationMethod</key>
    <string>JamfPro</string>
    <key>JamfServerURL</key>
    <string>https://jamf.company.com:8443</string>
    <key>JamfAPIUsername</key>
    <string>escrow_buddy_api</string>
    <key>ValidateSSLCertificate</key>
    <true/>
    
    <!-- Compliance Settings -->
    <key>EnableComplianceReporting</key>
    <true/>
    <key>ComplianceStandard</key>
    <string>NIST</string>
    <key>ComplianceReportInterval</key>
    <integer>7</integer>
    
    <!-- Advanced Settings -->
    <key>DebugLogging</key>
    <false/>
    <key>XPCTimeout</key>
    <integer>30</integer>
    <key>RetryAttempts</key>
    <integer>3</integer>
    <key>RetryDelay</key>
    <integer>300</integer>
</dict>
</plist>
```

### Environment-Specific Configurations

#### Development Environment
```bash
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy DebugLogging -bool YES
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy RotationIntervalDays -int 1
```

#### Staging Environment
```bash
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy RotationIntervalDays -int 7
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy ValidateSSLCertificate -bool NO
```

#### Production Environment
```bash
# Deploy via MDM profile only - no local modifications
```

## Daily Operations

### Routine Tasks

#### Morning Checks (Daily)
```bash
#!/bin/bash
# morning_check.sh

echo "=== Escrow Buddy Enhanced Daily Check ==="
date

# Check daemon status across fleet
for host in $(cat /path/to/host_list.txt); do
    echo "Checking $host..."
    ssh admin@$host "sudo launchctl list | grep escrow-buddy"
done

# Check for overnight failures
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND level == "ERROR"' \
    --start "$(date -v-1d '+%Y-%m-%d 00:00:00')" \
    --style compact | grep -c ERROR

# Verify compliance reports generated
ls -la /var/log/escrow_buddy_compliance/*.json | tail -5
```

#### Weekly Tasks
```bash
#!/bin/bash
# weekly_maintenance.sh

# Generate rotation statistics
echo "Keys rotated this week:"
grep "Rotation completed successfully" /var/log/escrow_buddy_daemon.log | \
    grep "$(date -v-7d '+%Y-%m')" | wc -l

# Check for stale keys
echo "Machines with keys > 90 days:"
# Query MDM for this information

# Verify all machines have daemon installed
# Compare MDM inventory with deployment records
```

### Manual Operations

#### Force Rotation on Single Machine
```bash
ssh admin@target-mac "sudo kill -USR1 \$(pgrep EscrowBuddyDaemon)"
```

#### Force Rotation on Multiple Machines
```bash
# Via Jamf Pro
jamf policy -trigger rotate-filevault -verbose

# Via script
for host in $(cat machines_needing_rotation.txt); do
    ssh admin@$host "sudo kill -USR1 \$(pgrep EscrowBuddyDaemon)" &
done
wait
```

#### Emergency Key Generation
```bash
# When automatic rotation fails
sudo fdesetup changerecovery -personal
# Save the displayed key securely
```

## Monitoring and Reporting

### Key Metrics to Monitor

| Metric | Target | Alert Threshold | Check Frequency |
|--------|--------|-----------------|-----------------|
| Rotation Success Rate | >95% | <90% | Daily |
| Average Key Age | <90 days | >100 days | Daily |
| Failed Rotations | <5% | >10% | Hourly |
| Daemon Uptime | >99% | <95% | Every 5 min |
| Compliance Score | 100% | <95% | Weekly |

### Monitoring Setup

#### Splunk Integration
```bash
# inputs.conf
[monitor:///var/log/escrow_buddy_*.log]
disabled = false
index = security
sourcetype = escrow_buddy

[monitor:///var/log/escrow_buddy_compliance/*.json]
disabled = false
index = compliance
sourcetype = _json
```

#### Prometheus Metrics
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'escrow_buddy'
    static_configs:
      - targets: ['localhost:9100']
    metric_path: /metrics/escrow_buddy
```

### Report Generation

#### Daily Status Report
```bash
#!/bin/bash
# generate_daily_report.sh

REPORT_DATE=$(date '+%Y-%m-%d')
REPORT_FILE="/var/reports/escrow_buddy_$REPORT_DATE.html"

cat > $REPORT_FILE << EOF
<html>
<head><title>Escrow Buddy Enhanced Daily Report - $REPORT_DATE</title></head>
<body>
<h1>Escrow Buddy Enhanced Status Report</h1>
<p>Date: $REPORT_DATE</p>

<h2>Statistics</h2>
<ul>
<li>Total Managed Devices: $(get_device_count)</li>
<li>Successful Rotations Today: $(get_rotation_count)</li>
<li>Failed Rotations: $(get_failure_count)</li>
<li>Average Key Age: $(get_avg_key_age) days</li>
<li>Compliance Score: $(get_compliance_score)%</li>
</ul>

<h2>Issues Requiring Attention</h2>
$(get_critical_issues)

</body>
</html>
EOF

# Email report
mail -s "Escrow Buddy Enhanced Daily Report" admin@company.com < $REPORT_FILE
```

## Security Best Practices

### Deployment Security

1. **Code Signing**
   - Always sign binaries with Developer ID
   - Notarize for macOS 10.15+
   - Verify signature before deployment

2. **Transport Security**
   - Use HTTPS for all API communication
   - Validate SSL certificates in production
   - Use certificate pinning for high-security environments

3. **Credential Management**
   - Never store user passwords
   - Use Keychain for API credentials
   - Rotate API keys quarterly

### Operational Security

#### Principle of Least Privilege
```bash
# Create dedicated API user with minimal permissions
# Jamf Pro example:
# - Read Computers
# - Update Computer Extension Attributes
# - Read Policies
# NO write access to policies or configuration
```

#### Audit Trail
```bash
# Enable comprehensive logging
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy AuditLevel -string "FULL"

# Forward logs to SIEM
syslog -s -l error -k Facility com.netflix.Escrow-Buddy | \
    nc siem.company.com 514
```

#### Access Control
```bash
# Restrict daemon modification
sudo chmod 755 /usr/local/bin/EscrowBuddyDaemon
sudo chflags uchg /usr/local/bin/EscrowBuddyDaemon

# Restrict configuration modification
sudo chmod 644 /Library/Preferences/com.netflix.escrow-buddy.plist
sudo chown root:wheel /Library/Preferences/com.netflix.escrow-buddy.plist
```

## Compliance Management

### Standards Compliance

#### NIST 800-171
- Requirement 3.5.10: Cryptographic key establishment and management
- Implementation: 90-day automatic rotation
- Evidence: Compliance reports in /var/log/escrow_buddy_compliance/

#### ISO 27001
- Control A.10.1.2: Key management
- Implementation: Full key lifecycle tracking
- Evidence: Key history in /var/db/escrow_buddy_keys.plist

#### PCI-DSS
- Requirement 3.6.4: Cryptographic key changes
- Implementation: Automatic rotation with escrow
- Evidence: MDM escrow verification logs

### Compliance Reporting

```bash
#!/bin/bash
# compliance_audit.sh

# Generate compliance report
sudo /usr/local/bin/EscrowBuddyDaemon --compliance-report

# Verify all devices compliant
COMPLIANT=$(jq '.compliance_status' /var/log/escrow_buddy_compliance/latest.json)

if [ "$COMPLIANT" != "true" ]; then
    echo "ALERT: Non-compliant devices detected"
    # Send alert to security team
fi

# Archive reports for audit
tar -czf compliance_$(date +%Y%m).tar.gz /var/log/escrow_buddy_compliance/
```

## Performance Tuning

### Optimization Settings

```bash
# For large deployments (>1000 devices)
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy BatchSize -int 50
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy StaggerDelay -int 300

# For high-security environments
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy VerifyEscrow -bool YES
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy DoubleCheck -bool YES

# For bandwidth-limited environments
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy CompressReports -bool YES
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy UploadBatchSize -int 10
```

### Resource Management

```bash
# Monitor resource usage
top -pid $(pgrep EscrowBuddyDaemon)

# Limit CPU usage if needed
sudo renice +10 $(pgrep EscrowBuddyDaemon)

# Check memory usage
sudo footprint EscrowBuddyDaemon
```

## Backup and Recovery

### Backup Strategy

```bash
#!/bin/bash
# backup_escrow_buddy.sh

BACKUP_DIR="/backup/escrow_buddy/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Backup configuration
cp /Library/Preferences/com.netflix.escrow-buddy.plist $BACKUP_DIR/

# Backup key history
cp /var/db/escrow_buddy_keys.plist $BACKUP_DIR/

# Backup compliance reports
tar -czf $BACKUP_DIR/compliance_reports.tar.gz /var/log/escrow_buddy_compliance/

# Backup daemon state
cp /var/db/escrow_buddy_daemon_status.plist $BACKUP_DIR/

echo "Backup completed to $BACKUP_DIR"
```

### Disaster Recovery

```bash
#!/bin/bash
# disaster_recovery.sh

RESTORE_DATE=$1
BACKUP_DIR="/backup/escrow_buddy/$RESTORE_DATE"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Backup not found for date: $RESTORE_DATE"
    exit 1
fi

# Stop daemon
sudo launchctl bootout system/com.netflix.escrow-buddy.daemon

# Restore configuration
sudo cp $BACKUP_DIR/com.netflix.escrow-buddy.plist /Library/Preferences/

# Restore key history
sudo cp $BACKUP_DIR/escrow_buddy_keys.plist /var/db/

# Restart daemon
sudo launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist

echo "Recovery completed from $RESTORE_DATE"
```

## Integration Guide

### SIEM Integration

```python
# siem_integration.py
import json
import requests
from datetime import datetime

def send_to_siem(event_data):
    """Send Escrow Buddy Enhanced events to SIEM"""
    
    siem_endpoint = "https://siem.company.com/api/events"
    
    event = {
        "timestamp": datetime.utcnow().isoformat(),
        "source": "escrow_buddy",
        "host": event_data.get("hostname"),
        "event_type": event_data.get("type"),
        "severity": event_data.get("severity", "INFO"),
        "details": event_data
    }
    
    response = requests.post(
        siem_endpoint,
        json=event,
        headers={"Authorization": "Bearer YOUR_API_KEY"}
    )
    
    return response.status_code == 200
```

### Ticketing System Integration

```bash
#!/bin/bash
# create_ticket_for_failures.sh

FAILURES=$(log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND message CONTAINS "rotation failed"' --last 1h)

if [ ! -z "$FAILURES" ]; then
    # Create ServiceNow ticket
    curl -X POST https://company.service-now.com/api/now/table/incident \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $SNOW_TOKEN" \
        -d '{
            "short_description": "Escrow Buddy Enhanced Rotation Failures Detected",
            "description": "'"$FAILURES"'",
            "priority": "3",
            "assignment_group": "Desktop Support"
        }'
fi
```

## Reference

### Command Reference

| Command | Purpose | Frequency |
|---------|---------|-----------|
| `sudo launchctl list \| grep escrow` | Check daemon status | As needed |
| `sudo kill -USR1 $(pgrep EscrowBuddyDaemon)` | Force rotation | As needed |
| `sudo kill -HUP $(pgrep EscrowBuddyDaemon)` | Reload config | After changes |
| `sudo /usr/local/bin/EscrowBuddyDaemon --status` | Get current status | Daily |
| `sudo /usr/local/bin/EscrowBuddyDaemon --verify-escrow` | Verify key escrow | After rotation |
| `log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"'` | View logs | Troubleshooting |

### File Locations

| File/Directory | Purpose | Permissions |
|----------------|---------|-------------|
| `/usr/local/bin/EscrowBuddyDaemon` | Daemon binary | 755 root:wheel |
| `/Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist` | LaunchDaemon | 644 root:wheel |
| `/Library/Preferences/com.netflix.escrow-buddy.plist` | Configuration | 644 root:wheel |
| `/var/db/escrow_buddy_keys.plist` | Key history | 600 root:wheel |
| `/var/db/escrow_buddy_daemon_status.plist` | Daemon state | 644 root:wheel |
| `/var/log/escrow_buddy_daemon.log` | Daemon logs | 644 root:wheel |
| `/var/log/escrow_buddy_compliance/` | Compliance reports | 755 root:admin |

### Exit Codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success | None |
| 1 | General failure | Check logs |
| 2 | Configuration error | Verify configuration |
| 3 | MDM connection failed | Check MDM settings |
| 4 | FileVault not enabled | Enable FileVault |
| 5 | Rotation in progress | Wait and retry |
| 6 | Permission denied | Check permissions |

### Support Matrix

| macOS Version | Support Status | Notes |
|---------------|----------------|-------|
| 10.14 | Unsupported | Original Escrow Buddy only |
| 10.15 | Supported | Full functionality |
| 11.x | Supported | Full functionality |
| 12.x | Supported | Full functionality |
| 13.x | Supported | Full functionality |
| 14.x | Supported | Requires signed/notarized binary |

## Appendix

### Sample Automation Scripts

Available in `/Scripts/` directory:
- `daily_health_check.sh` - Automated health monitoring
- `bulk_rotation.sh` - Mass rotation trigger
- `compliance_audit.sh` - Compliance verification
- `emergency_recovery.sh` - Disaster recovery

### Glossary

- **Escrow**: Secure storage of recovery key with third party (MDM)
- **Recovery Key**: Alternative to user password for FileVault unlock
- **XPC**: Inter-process communication on macOS
- **MDM**: Mobile Device Management
- **Compliance Standard**: Regulatory framework (NIST, ISO, etc.)

### Change Log

See CHANGELOG.md for version history and updates.

---

*End of Administrator Manual - Version 2.0*