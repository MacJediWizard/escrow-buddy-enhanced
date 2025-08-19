# Escrow Buddy Enhanced - Troubleshooting Guide

## Table of Contents
1. [Common Issues](#common-issues)
2. [Diagnostic Commands](#diagnostic-commands)
3. [Log Analysis](#log-analysis)
4. [Error Messages](#error-messages)
5. [Recovery Procedures](#recovery-procedures)
6. [FAQ](#faq)

## Common Issues

### Issue 1: Daemon Not Starting

**Symptoms:**
- No EscrowBuddyDaemon process running
- Rotation not occurring automatically
- XPC connection errors

**Diagnosis:**
```bash
# Check if daemon is loaded
sudo launchctl list | grep escrow-buddy

# Check for errors
sudo launchctl print system/com.netflix.escrow-buddy.daemon

# Check permissions
ls -la /usr/local/bin/EscrowBuddyDaemon
ls -la /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

**Solutions:**

1. **Reload the daemon:**
```bash
sudo launchctl bootout system/com.netflix.escrow-buddy.daemon
sudo launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

2. **Fix permissions:**
```bash
sudo chmod 755 /usr/local/bin/EscrowBuddyDaemon
sudo chown root:wheel /usr/local/bin/EscrowBuddyDaemon
sudo chmod 644 /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
sudo chown root:wheel /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

3. **Check for code signing issues:**
```bash
codesign -dvv /usr/local/bin/EscrowBuddyDaemon
# If unsigned or invalid:
sudo xattr -cr /usr/local/bin/EscrowBuddyDaemon
```

---

### Issue 2: Rotation Failing

**Symptoms:**
- Keys not rotating on schedule
- Error messages in logs
- MDM shows old recovery keys

**Diagnosis:**
```bash
# Check rotation status
sudo /usr/local/bin/EscrowBuddyDaemon --status

# Check MDM configuration
sudo plutil -p /Library/Preferences/com.netflix.escrow-buddy.plist

# Test MDM connection
sudo /usr/local/bin/EscrowBuddyDaemon --test-mdm

# Check last rotation attempt
sudo cat /var/db/escrow_buddy_daemon_status.plist
```

**Solutions:**

1. **Verify MDM configuration:**
```bash
# Check MDM method
sudo defaults read /Library/Preferences/com.netflix.escrow-buddy MDMRotationMethod

# For Jamf Pro
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy JamfServerURL "https://your.jamf.server:8443"

# Test connection
curl -u username:password https://your.jamf.server:8443/JSSResource/computers/serialnumber/$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
```

2. **Check FileVault status:**
```bash
fdesetup status
# Must show "FileVault is On"

# Check for institutional key
sudo fdesetup hasinstitutionalrecoverykey
```

3. **Force rotation:**
```bash
# Trigger immediate rotation
sudo kill -USR1 $(pgrep EscrowBuddyDaemon)

# Monitor in real-time
log stream --predicate 'subsystem == "com.netflix.Escrow-Buddy"'
```

---

### Issue 3: XPC Communication Failure

**Symptoms:**
- "XPC connection invalid" errors
- Auth plugin not communicating with daemon
- Duplicate rotation attempts

**Diagnosis:**
```bash
# Check XPC service registration
sudo launchctl print system/com.netflix.escrow-buddy.daemon | grep "mach services"

# Test XPC connection
sudo /usr/local/bin/EscrowBuddyDaemon --test-xpc

# Check for port conflicts
sudo lsof -i | grep escrow
```

**Solutions:**

1. **Reset XPC service:**
```bash
# Stop all components
sudo launchctl bootout system/com.netflix.escrow-buddy.daemon
sudo killall -9 EscrowBuddyDaemon 2>/dev/null

# Clear XPC cache
sudo rm -rf /var/db/com.apple.xpc.launchd/disabled.*.plist

# Restart
sudo launchctl bootstrap system /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
```

2. **Verify Mach service name:**
```bash
# Check plist for correct service name
grep -A2 "MachServices" /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
# Should show: com.netflix.escrow-buddy.xpc
```

---

### Issue 4: Compliance Reports Not Generating

**Symptoms:**
- No reports in /var/log/escrow_buddy_compliance/
- Compliance status unknown
- MDM not receiving compliance data

**Diagnosis:**
```bash
# Check if reporting is enabled
sudo defaults read /Library/Preferences/com.netflix.escrow-buddy EnableComplianceReporting

# Check compliance directory
ls -la /var/log/escrow_buddy_compliance/

# Test report generation
sudo /usr/local/bin/EscrowBuddyDaemon --generate-report
```

**Solutions:**

1. **Enable compliance reporting:**
```bash
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy EnableComplianceReporting -bool YES
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy ComplianceStandard "NIST"
```

2. **Fix permissions:**
```bash
sudo mkdir -p /var/log/escrow_buddy_compliance
sudo chmod 755 /var/log/escrow_buddy_compliance
sudo chown root:admin /var/log/escrow_buddy_compliance
```

---

### Issue 5: Jamf API Connection Issues

**Symptoms:**
- "Failed to authenticate with Jamf" errors
- Cannot verify key escrow
- API timeout errors

**Diagnosis:**
```bash
# Test Jamf connectivity
curl -k https://your.jamf.server:8443/healthCheck.html

# Check stored credentials
security find-generic-password -s "com.netflix.escrow-buddy.jamf"

# Test API authentication
curl -u username:password -H "Accept: application/json" \
  https://your.jamf.server:8443/JSSResource/computers/id/1
```

**Solutions:**

1. **Update API credentials:**
```bash
# Remove old credential
security delete-generic-password -s "com.netflix.escrow-buddy.jamf"

# Add new credential
security add-generic-password -a "api_username" -s "com.netflix.escrow-buddy.jamf" -w "new_password"
```

2. **Configure SSL/TLS:**
```bash
# For self-signed certificates
sudo defaults write /Library/Preferences/com.netflix.escrow-buddy ValidateSSLCertificate -bool NO

# Or add certificate to keychain
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /path/to/cert.pem
```

---

## Diagnostic Commands

### Quick Health Check
```bash
#!/bin/bash
# Save as escrow_buddy_health.sh

echo "=== Escrow Buddy Enhanced Health Check ==="
echo

echo "1. Daemon Status:"
sudo launchctl list | grep escrow-buddy || echo "  ❌ Not loaded"

echo
echo "2. Process Running:"
ps aux | grep -v grep | grep EscrowBuddyDaemon || echo "  ❌ Not running"

echo
echo "3. Last Rotation:"
sudo plutil -p /var/db/escrow_buddy_daemon_status.plist 2>/dev/null | grep lastRotation || echo "  ❌ Never"

echo
echo "4. Configuration:"
sudo defaults read /Library/Preferences/com.netflix.escrow-buddy 2>/dev/null | head -5 || echo "  ❌ Not configured"

echo
echo "5. Recent Errors:"
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND level == "ERROR"' --last 1h --style compact | tail -5
```

### Comprehensive Diagnostic
```bash
#!/bin/bash
# Save as escrow_buddy_diagnose.sh

LOG_DIR="/tmp/escrow_buddy_diagnostic_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "Collecting diagnostic information to $LOG_DIR..."

# System info
system_profiler SPSoftwareDataType > "$LOG_DIR/system_info.txt"
system_profiler SPHardwareDataType >> "$LOG_DIR/system_info.txt"

# FileVault status
fdesetup status > "$LOG_DIR/filevault_status.txt"
sudo fdesetup list >> "$LOG_DIR/filevault_status.txt"

# Daemon status
sudo launchctl print system/com.netflix.escrow-buddy.daemon > "$LOG_DIR/daemon_status.txt" 2>&1

# Configuration
sudo defaults read /Library/Preferences/com.netflix.escrow-buddy > "$LOG_DIR/configuration.plist" 2>&1

# Logs
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1d > "$LOG_DIR/escrow_buddy_logs.txt"

# File permissions
ls -la /usr/local/bin/EscrowBuddyDaemon > "$LOG_DIR/permissions.txt"
ls -la /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist >> "$LOG_DIR/permissions.txt"
ls -la /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle >> "$LOG_DIR/permissions.txt"

# Create archive
tar -czf "$LOG_DIR.tar.gz" -C /tmp "$(basename $LOG_DIR)"
echo "Diagnostic archive created: $LOG_DIR.tar.gz"
```

## Log Analysis

### Understanding Log Levels

| Level | Meaning | Action Required |
|-------|---------|-----------------|
| ERROR | Critical failure | Immediate attention |
| WARNING | Potential issue | Monitor closely |
| INFO | Normal operation | No action |
| DEBUG | Detailed information | Development only |

### Key Log Patterns

**Successful Rotation:**
```
INFO: Starting FileVault key rotation
INFO: MDM rotation completed successfully with key ID: [UUID]
INFO: Rotation completed successfully
```

**Failed Rotation:**
```
ERROR: MDM rotation not available
ERROR: Failed to report rotation event
ERROR: MDM rotation failed or timed out
```

**Configuration Issues:**
```
WARNING: Configuration file not found, using defaults
ERROR: Invalid configuration value for RotationIntervalDays
```

### Log Filtering Examples

```bash
# Show only errors
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND level == "ERROR"' --last 1d

# Show rotation events
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND message CONTAINS "rotation"' --last 1d

# Show daemon startup
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy" AND message CONTAINS "starting"' --last 1d

# Export logs for analysis
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 7d --style json > escrow_buddy_logs.json
```

## Error Messages

### Common Error Messages and Solutions

| Error Message | Cause | Solution |
|--------------|-------|----------|
| "MDM rotation not available" | MDM not configured | Configure MDM method in preferences |
| "XPC connection invalid" | Daemon not running | Restart daemon service |
| "Failed to authenticate with Jamf" | Invalid API credentials | Update Jamf API credentials |
| "FileVault is not enabled" | FileVault off | Enable FileVault first |
| "No valid recovery key found" | Key missing or corrupted | Generate new key manually |
| "Rotation already in progress" | Duplicate rotation attempt | Wait for current rotation to complete |
| "Configuration file not found" | Missing preferences | Deploy configuration profile |
| "Permission denied" | Incorrect file permissions | Fix permissions (see solutions) |

## Recovery Procedures

### Emergency Key Rotation

If automatic rotation fails completely:

```bash
#!/bin/bash
# Manual emergency rotation

# 1. Generate new recovery key (requires user password)
echo "Enter admin username:"
read admin_user
sudo fdesetup changerecovery -personal -user "$admin_user"

# 2. Record the new key securely
echo "SAVE THE RECOVERY KEY DISPLAYED ABOVE!"

# 3. Verify new key works
sudo fdesetup validaterecovery

# 4. Update MDM manually if needed
# (Check your MDM documentation for manual key upload)
```

### Complete Reset

If you need to completely reset Escrow Buddy Enhanced:

```bash
#!/bin/bash
# Complete reset script

echo "This will completely reset Escrow Buddy Enhanced. Continue? (y/n)"
read confirm
if [ "$confirm" != "y" ]; then exit 1; fi

# Stop daemon
sudo launchctl bootout system/com.netflix.escrow-buddy.daemon

# Remove all files
sudo rm -rf /Library/Security/SecurityAgentPlugins/Escrow\ Buddy.bundle
sudo rm -f /usr/local/bin/EscrowBuddyDaemon
sudo rm -f /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist
sudo rm -f /Library/Preferences/com.netflix.escrow-buddy.plist
sudo rm -rf /var/db/escrow_buddy*
sudo rm -rf /var/log/escrow_buddy*

# Reset authorization database
sudo sqlite3 /var/db/auth.db "DELETE FROM mechanisms WHERE plugin='Escrow Buddy';"

echo "Reset complete. Reinstall from package to start fresh."
```

### Rollback to Original Escrow Buddy

If you need to rollback to the original version:

```bash
#!/bin/bash
# Rollback script

# Remove enhanced components only
sudo launchctl bootout system/com.netflix.escrow-buddy.daemon
sudo rm -f /usr/local/bin/EscrowBuddyDaemon
sudo rm -f /Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist

# Keep original Escrow Buddy
echo "Enhanced features removed. Original Escrow Buddy remains functional."
echo "Keys will now only rotate on user login/logout."
```

## FAQ

### Q: How often should keys rotate?
**A:** Default is 90 days. Adjust based on your compliance requirements:
- NIST 800-171: 90 days
- PCI-DSS: 90-365 days
- HIPAA: No specific requirement, 90 days recommended

### Q: Can I rotate keys manually?
**A:** Yes, use: `sudo kill -USR1 $(pgrep EscrowBuddyDaemon)`

### Q: Does rotation require user interaction?
**A:** No, the daemon rotates keys in the background without user involvement.

### Q: What happens if rotation fails?
**A:** The daemon will retry at the next scheduled interval. Check logs for specific errors.

### Q: Can I use this without MDM?
**A:** No, MDM is required for secure key rotation without storing credentials.

### Q: How do I know if a key was successfully escrowed?
**A:** Check your MDM console for the updated recovery key, or use:
```bash
sudo /usr/local/bin/EscrowBuddyDaemon --verify-escrow
```

### Q: Is the old key still valid after rotation?
**A:** No, only the new key will work for recovery after rotation.

### Q: Can I customize the compliance reports?
**A:** Yes, modify ComplianceReporter.m and rebuild the project.

### Q: What macOS versions are supported?
**A:** macOS 10.15 (Catalina) and later. Earlier versions may work but are untested.

### Q: How do I enable debug logging?
**A:** Run: `sudo /usr/local/bin/EscrowBuddyDaemon --debug`

## Getting Help

If you've tried all troubleshooting steps:

1. **Collect diagnostics:**
   ```bash
   ./escrow_buddy_diagnose.sh
   ```

2. **Check GitHub issues:**
   - Search existing issues for your problem
   - Include diagnostic archive when opening new issue

3. **Contact support:**
   - Include macOS version
   - Include MDM type and version
   - Include diagnostic archive
   - Describe steps to reproduce

## Quick Reference Card

```bash
# Essential Commands
sudo launchctl list | grep escrow              # Check if loaded
sudo kill -USR1 $(pgrep EscrowBuddyDaemon)    # Trigger rotation
sudo kill -HUP $(pgrep EscrowBuddyDaemon)     # Reload config
log show --predicate 'subsystem == "com.netflix.Escrow-Buddy"' --last 1h  # View logs
sudo /usr/local/bin/EscrowBuddyDaemon --status # Check status

# File Locations
/usr/local/bin/EscrowBuddyDaemon              # Daemon binary
/Library/LaunchDaemons/com.netflix.escrow-buddy.daemon.plist  # LaunchDaemon
/Library/Preferences/com.netflix.escrow-buddy.plist  # Configuration
/var/db/escrow_buddy_keys.plist               # Key history
/var/log/escrow_buddy_compliance/             # Compliance reports
```