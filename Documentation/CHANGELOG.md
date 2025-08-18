# Changelog

All notable changes to Escrow Buddy Enhanced will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-08-18

### Added
- **Background Daemon** - Automatic key rotation without user logout
- **MDMRotationHandler** - Secure rotation via MDM commands (no credential storage)
- **RotationManager** - Centralized rotation logic and scheduling
- **ConfigurationManager** - MDM profile and preference management  
- **KeyLifecycleTracker** - Complete key history and metadata tracking
- **ComplianceReporter** - Multi-standard compliance reporting (NIST, ISO27001, PCI-DSS, HIPAA, SOC2)
- **JamfAPIClient** - Full Jamf Pro API integration
- **EnhancedLogger** - Comprehensive audit logging
- **XPC Communication** - Daemon-plugin coordination to prevent duplicate rotations
- **Multiple rotation methods** - Jamf Pro, Apple MDM, Profile-based, Custom script
- **Comprehensive documentation** - Deployment, troubleshooting, and administrator guides

### Changed
- Auth plugin now coordinates with daemon via XPC
- Enhanced Swift mechanisms for daemon awareness
- Improved error handling and recovery
- Updated build system with Makefile

### Security
- Eliminated need for credential storage
- All FileVault operations now performed via MDM
- Added code signing support
- Implemented secure XPC validation

### Fixed
- Keys can now rotate without user logout
- Resolved race conditions between login and scheduled rotations
- Improved reliability of key escrow verification

## [1.0.0] - Previous Version

Original Escrow Buddy by Netflix - See original repository for details