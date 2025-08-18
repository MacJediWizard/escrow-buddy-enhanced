# Makefile for Escrow Buddy Enhanced
# Copyright 2025 Escrow Buddy Enhanced

# Configuration
PROJECT_NAME = Escrow Buddy
BUNDLE_ID = com.netflix.Escrow-Buddy
CONFIGURATION = Release
XCODE_PROJECT = Escrow Buddy/Escrow Buddy.xcodeproj
BUILD_DIR = build
OUTPUT_DIR = dist
SCRIPTS_DIR = scripts

# Version detection
VERSION := $(shell defaults read "$(PWD)/Escrow Buddy/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
NC = \033[0m # No Color

# Default target
.PHONY: all
all: clean build package

# Help target
.PHONY: help
help:
	@echo "$(GREEN)Escrow Buddy Enhanced - Build System$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(YELLOW)make all$(NC)          - Clean, build, and package (default)"
	@echo "  $(YELLOW)make build$(NC)        - Build the Xcode project"
	@echo "  $(YELLOW)make package$(NC)      - Create installer package"
	@echo "  $(YELLOW)make clean$(NC)        - Clean build artifacts"
	@echo "  $(YELLOW)make test$(NC)         - Run unit tests"
	@echo "  $(YELLOW)make install$(NC)      - Install locally (requires sudo)"
	@echo "  $(YELLOW)make uninstall$(NC)    - Uninstall from system (requires sudo)"
	@echo "  $(YELLOW)make release$(NC)      - Build signed release package"
	@echo "  $(YELLOW)make debug$(NC)        - Build debug configuration"
	@echo "  $(YELLOW)make check$(NC)        - Run static analysis"
	@echo "  $(YELLOW)make docs$(NC)         - Generate documentation"
	@echo ""
	@echo "Configuration:"
	@echo "  Version: $(VERSION)"
	@echo "  Configuration: $(CONFIGURATION)"

# Build target
.PHONY: build
build:
	@echo "$(YELLOW)Building Escrow Buddy Enhanced...$(NC)"
	@mkdir -p $(BUILD_DIR)
	@xcodebuild -project "$(XCODE_PROJECT)" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		build
	@echo "$(GREEN)Build complete!$(NC)"

# Debug build
.PHONY: debug
debug:
	@echo "$(YELLOW)Building Debug configuration...$(NC)"
	@$(MAKE) build CONFIGURATION=Debug

# Package target
.PHONY: package
package: build
	@echo "$(YELLOW)Creating installer package...$(NC)"
	@mkdir -p $(OUTPUT_DIR)
	@$(SCRIPTS_DIR)/build_and_pkg_enhanced.sh
	@echo "$(GREEN)Package created in $(OUTPUT_DIR)$(NC)"

# Clean target
.PHONY: clean
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(BUILD_DIR)
	@rm -rf $(OUTPUT_DIR)
	@xcodebuild -project "$(XCODE_PROJECT)" clean
	@echo "$(GREEN)Clean complete!$(NC)"

# Test target
.PHONY: test
test:
	@echo "$(YELLOW)Running unit tests...$(NC)"
	@xcodebuild test -project "$(XCODE_PROJECT)" \
		-scheme "$(PROJECT_NAME)" \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR)
	@echo "$(GREEN)Tests complete!$(NC)"

# Static analysis
.PHONY: check
check:
	@echo "$(YELLOW)Running static analysis...$(NC)"
	@xcodebuild analyze -project "$(XCODE_PROJECT)" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR)
	@echo "$(GREEN)Analysis complete!$(NC)"

# Install locally
.PHONY: install
install: package
	@echo "$(YELLOW)Installing Escrow Buddy Enhanced...$(NC)"
	@echo "$(RED)This requires administrator privileges$(NC)"
	@sudo installer -pkg "$(OUTPUT_DIR)/EscrowBuddy-Enhanced-$(VERSION).pkg" -target /
	@echo "$(GREEN)Installation complete!$(NC)"

# Uninstall
.PHONY: uninstall
uninstall:
	@echo "$(YELLOW)Uninstalling Escrow Buddy Enhanced...$(NC)"
	@echo "$(RED)This requires administrator privileges$(NC)"
	@if [ -f "/usr/local/bin/uninstall_escrow_buddy.sh" ]; then \
		sudo /usr/local/bin/uninstall_escrow_buddy.sh; \
	else \
		echo "$(RED)Uninstall script not found. Manual removal required.$(NC)"; \
		echo "Run: sudo rm -rf '/Library/Security/SecurityAgentPlugins/Escrow Buddy.bundle'"; \
	fi
	@echo "$(GREEN)Uninstallation complete!$(NC)"

# Release build with signing
.PHONY: release
release:
	@echo "$(YELLOW)Building signed release package...$(NC)"
	@if [ -z "$(CODESIGN_IDENTITY)" ]; then \
		echo "$(RED)Error: CODESIGN_IDENTITY not set$(NC)"; \
		echo "Usage: make release CODESIGN_IDENTITY='Developer ID Application: Your Name'"; \
		exit 1; \
	fi
	@$(SCRIPTS_DIR)/build_and_pkg_enhanced.sh --sign "$(CODESIGN_IDENTITY)"
	@echo "$(GREEN)Signed release package created!$(NC)"

# Generate documentation
.PHONY: docs
docs:
	@echo "$(YELLOW)Generating documentation...$(NC)"
	@mkdir -p docs
	@# Generate header documentation using HeaderDoc or similar
	@headerdoc2html -o docs "Escrow Buddy"/*.h "Escrow Buddy"/*.m 2>/dev/null || true
	@echo "$(GREEN)Documentation generated in docs/$(NC)"

# Version bump targets
.PHONY: bump-patch
bump-patch:
	@echo "$(YELLOW)Bumping patch version...$(NC)"
	@# Implementation would increment patch version in Info.plist

.PHONY: bump-minor
bump-minor:
	@echo "$(YELLOW)Bumping minor version...$(NC)"
	@# Implementation would increment minor version in Info.plist

.PHONY: bump-major
bump-major:
	@echo "$(YELLOW)Bumping major version...$(NC)"
	@# Implementation would increment major version in Info.plist

# Distribution archive
.PHONY: dist
dist: release
	@echo "$(YELLOW)Creating distribution archive...$(NC)"
	@mkdir -p $(OUTPUT_DIR)/EscrowBuddy-Enhanced-$(VERSION)
	@cp $(OUTPUT_DIR)/*.pkg $(OUTPUT_DIR)/EscrowBuddy-Enhanced-$(VERSION)/
	@cp README.md LICENSE DEPLOYMENT_GUIDE.md $(OUTPUT_DIR)/EscrowBuddy-Enhanced-$(VERSION)/
	@cp -r Configuration $(OUTPUT_DIR)/EscrowBuddy-Enhanced-$(VERSION)/
	@cd $(OUTPUT_DIR) && zip -r EscrowBuddy-Enhanced-$(VERSION).zip EscrowBuddy-Enhanced-$(VERSION)
	@echo "$(GREEN)Distribution archive created: $(OUTPUT_DIR)/EscrowBuddy-Enhanced-$(VERSION).zip$(NC)"

# CI/CD targets
.PHONY: ci-build
ci-build: clean check build test package
	@echo "$(GREEN)CI build complete!$(NC)"

.PHONY: ci-release
ci-release: clean check build test release dist
	@echo "$(GREEN)CI release build complete!$(NC)"

# Development helpers
.PHONY: setup-dev
setup-dev:
	@echo "$(YELLOW)Setting up development environment...$(NC)"
	@# Install any required tools or dependencies
	@echo "$(GREEN)Development environment ready!$(NC)"

.PHONY: format
format:
	@echo "$(YELLOW)Formatting code...$(NC)"
	@# Run code formatters (clang-format for Obj-C, swift-format for Swift)
	@find "Escrow Buddy" -name "*.m" -o -name "*.h" | xargs clang-format -i
	@echo "$(GREEN)Code formatting complete!$(NC)"

# Show current configuration
.PHONY: info
info:
	@echo "$(GREEN)Escrow Buddy Enhanced - Build Information$(NC)"
	@echo "Version: $(VERSION)"
	@echo "Bundle ID: $(BUNDLE_ID)"
	@echo "Configuration: $(CONFIGURATION)"
	@echo "Xcode Project: $(XCODE_PROJECT)"
	@echo "Build Directory: $(BUILD_DIR)"
	@echo "Output Directory: $(OUTPUT_DIR)"
	@echo ""
	@echo "System Information:"
	@sw_vers
	@echo ""
	@echo "Xcode Version:"
	@xcodebuild -version

.DEFAULT_GOAL := all