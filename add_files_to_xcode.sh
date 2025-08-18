#!/bin/bash

#
#  add_files_to_xcode.sh
#  Script to add new files to Xcode project
#

set -e

echo "=== Adding New Files to Xcode Project ==="
echo

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/Escrow Buddy.xcodeproj/project.pbxproj"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if project file exists
if [ ! -f "$PROJECT_FILE" ]; then
    echo -e "${RED}Error: Xcode project file not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Files to add to Xcode project:${NC}"
echo "----------------------------------------"

# List of new files to add
NEW_FILES=(
    "Escrow Buddy/RotationManager.h"
    "Escrow Buddy/RotationManager.m"
    "Escrow Buddy/ConfigurationManager.h"
    "Escrow Buddy/ConfigurationManager.m"
    "Escrow Buddy/KeyLifecycleTracker.h"
    "Escrow Buddy/KeyLifecycleTracker.m"
    "Escrow Buddy/EnhancedLogger.h"
    "Escrow Buddy/EnhancedLogger.m"
    "Escrow Buddy/JamfAPIClient.h"
    "Escrow Buddy/JamfAPIClient.m"
    "Escrow Buddy/ComplianceReporter.h"
    "Escrow Buddy/ComplianceReporter.m"
    "Escrow Buddy/MDMRotationHandler.h"
    "Escrow Buddy/MDMRotationHandler.m"
    "Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyDaemon.h"
    "Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyDaemon.m"
    "Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyXPCClient.h"
    "Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyXPCClient.m"
    "Escrow Buddy/EscrowBuddyDaemon/EscrowBuddyXPCProtocol.h"
    "Escrow Buddy/EscrowBuddyDaemon/main.m"
    "Escrow Buddy/Mechanisms/EnhancedInvoke.swift"
    "Escrow Buddy/Mechanisms/EnhancedInvokeWithDaemon.swift"
)

# Check which files exist
EXISTING_FILES=()
MISSING_FILES=()

for file in "${NEW_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$file" ]; then
        EXISTING_FILES+=("$file")
        echo -e "${GREEN}✅${NC} $file"
    else
        MISSING_FILES+=("$file")
        echo -e "${RED}❌${NC} $file (not found)"
    fi
done

echo
echo -e "${YELLOW}Summary:${NC}"
echo "  Existing files: ${#EXISTING_FILES[@]}"
echo "  Missing files: ${#MISSING_FILES[@]}"

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo
    echo -e "${RED}Warning: Some files are missing and won't be added${NC}"
fi

echo
echo -e "${YELLOW}Manual Steps Required:${NC}"
echo "----------------------------------------"
echo "1. Open Escrow Buddy.xcodeproj in Xcode"
echo
echo "2. Add the following files to the project:"
for file in "${EXISTING_FILES[@]}"; do
    echo "   - $file"
done
echo
echo "3. For each file:"
echo "   a. Right-click on 'Escrow Buddy' group in project navigator"
echo "   b. Select 'Add Files to \"Escrow Buddy\"...'"
echo "   c. Navigate to the file and select it"
echo "   d. Ensure 'Copy items if needed' is unchecked (files are already in place)"
echo "   e. Ensure 'Escrow Buddy' target is selected"
echo "   f. Click 'Add'"
echo
echo "4. For Swift files, ensure they're added to the correct target:"
echo "   - EnhancedInvoke.swift -> Escrow Buddy target"
echo "   - EnhancedInvokeWithDaemon.swift -> Escrow Buddy target"
echo
echo "5. For daemon files, ensure they're in a separate 'EscrowBuddyDaemon' group:"
echo "   - Create a new group: Right-click 'Escrow Buddy' -> New Group -> Name it 'EscrowBuddyDaemon'"
echo "   - Add daemon files to this group"
echo
echo "6. Update Build Phases:"
echo "   a. Go to project settings -> Escrow Buddy target -> Build Phases"
echo "   b. In 'Compile Sources', ensure all .m and .swift files are listed"
echo "   c. In 'Headers', ensure all .h files are listed (if building a framework)"
echo
echo "7. Clean and rebuild the project:"
echo "   a. Product -> Clean Build Folder (Cmd+Shift+K)"
echo "   b. Product -> Build (Cmd+B)"
echo

# Alternative: Try to add files programmatically using xcodeproj Ruby gem
echo -e "${YELLOW}Alternative: Install xcodeproj gem for automated addition${NC}"
echo "----------------------------------------"
echo "If you have Ruby installed, you can automate this process:"
echo
echo "1. Install xcodeproj gem:"
echo "   sudo gem install xcodeproj"
echo
echo "2. Run the automated script:"
echo "   ruby add_files_to_xcode.rb"
echo

# Create Ruby script for automated addition
cat > "$PROJECT_DIR/add_files_to_xcode.rb" << 'EOF'
#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'Escrow Buddy.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main group
main_group = project.main_group['Escrow Buddy']

# Create daemon group if it doesn't exist
daemon_group = main_group['EscrowBuddyDaemon'] || main_group.new_group('EscrowBuddyDaemon')

# Files to add
files_to_add = {
  'Escrow Buddy' => [
    'RotationManager.h',
    'RotationManager.m',
    'ConfigurationManager.h',
    'ConfigurationManager.m',
    'KeyLifecycleTracker.h',
    'KeyLifecycleTracker.m',
    'EnhancedLogger.h',
    'EnhancedLogger.m',
    'JamfAPIClient.h',
    'JamfAPIClient.m',
    'ComplianceReporter.h',
    'ComplianceReporter.m',
    'MDMRotationHandler.h',
    'MDMRotationHandler.m',
    'Mechanisms/EnhancedInvoke.swift',
    'Mechanisms/EnhancedInvokeWithDaemon.swift'
  ],
  'EscrowBuddyDaemon' => [
    'EscrowBuddyDaemon.h',
    'EscrowBuddyDaemon.m',
    'EscrowBuddyXPCClient.h',
    'EscrowBuddyXPCClient.m',
    'EscrowBuddyXPCProtocol.h',
    'main.m'
  ]
}

# Get the target
target = project.targets.find { |t| t.name == 'Escrow Buddy' }

# Add files
files_to_add.each do |group_name, files|
  group = group_name == 'Escrow Buddy' ? main_group : daemon_group
  
  files.each do |file_name|
    file_path = group_name == 'Escrow Buddy' ? 
      "Escrow Buddy/#{file_name}" : 
      "Escrow Buddy/EscrowBuddyDaemon/#{file_name}"
    
    # Check if file exists
    next unless File.exist?(file_path)
    
    # Check if already in project
    next if project.files.find { |f| f.path == file_path }
    
    # Add file reference
    file_ref = group.new_file(file_path)
    
    # Add to build phase if it's a source file
    if file_name.end_with?('.m', '.swift')
      target.source_build_phase.add_file_reference(file_ref)
      puts "Added #{file_path} to compile sources"
    else
      puts "Added #{file_path} to project"
    end
  end
end

# Save the project
project.save
puts "\nProject updated successfully!"
EOF

chmod +x "$PROJECT_DIR/add_files_to_xcode.rb"

echo -e "${GREEN}Created add_files_to_xcode.rb for automated addition${NC}"
echo
echo "=== Setup Complete ==="