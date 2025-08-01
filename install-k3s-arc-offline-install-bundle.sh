#!/bin/bash
# 2025.07.31 - CSB Dev <csbdev@cspire.com>
#
# K3s + Azure Arc Offline Installation Bundle Installer
# This script installs offline bundles for K3s + Azure Arc setup
#
# Usage: ./install-k3s-arc-offline-install-bundle.sh [OPTIONS] BUNDLE_FILE

set -e

# Color output for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Status glyphs for consistent display
CHECK="✅"
CROSS="❌"
WARN="⚠️"
INFO="ℹ️"
ROCKET="🚀"
GEAR="⚙️"
CLOUD="☁️"
LOCK="🔐"
CLOCK="🕒"
WRENCH="🔧"
REFRESH="🔄"
HOURGLASS="⏳"
TEST="🧪"
COMPUTER="🖥️"
SHIP="🚢"
LINK="🔗"
BOOKS="📚"
GLOBE="🌐"
CHART="📊"
MEMO="📝"
CLIPBOARD="📋"
CELEBRATION="🎉"
LIGHTBULB="💡"
FOLDER="📁"
ARROW="→"
PACKAGE="📦"
DOWNLOAD="⬇️"
UPLOAD="⬆️"

# Secure sudo password storage (memory only)
SUDO_PASSWORD=""

# Output mode control
VERBOSE=false
QUIET=false
UPGRADE=false

# Installation tracking
BUNDLE_FILE=""
TEMP_DIR=""
BUNDLE_DIR=""
SYSTEM_ARCH=""
HELM_ARCH=""
KUBECTL_ARCH=""
CURRENT_STEP=0
TOTAL_STEPS=9  # Updated to include system updates, dependencies, and K3s installation

# Installation paths
OFFLINE_BASE_DIR="$HOME/.k3s-arc-offline"
COMPLETION_MARKER="$OFFLINE_BASE_DIR/components-installed"
AZURE_CLI_DIR="$OFFLINE_BASE_DIR/azure-cli"

log() {
	if [[ "$VERBOSE" == "true" ]]; then
		echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
	elif [[ "$QUIET" != "true" ]]; then
		echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
	fi
}

status() {
	if [[ "$QUIET" != "true" ]]; then
		echo -e "${BOLD}${CYAN}$1${NC}"
	fi
}

success() {
	if [[ "$QUIET" != "true" ]]; then
		echo -e "${GREEN}${CHECK} $1${NC}"
	fi
}

warn() {
	clear_progress
	echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
	clear_progress
	echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
	exit 1
}

info() {
	if [[ "$QUIET" != "true" ]]; then
		echo -e "${BLUE}${INFO} $1${NC}"
	fi
}

verbose_log() {
	if [[ "$VERBOSE" == "true" ]]; then
		echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
	fi
}

# Clear current line
clear_line() {
	if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
		printf "\r%*s\r" 80 ""
	fi
}

clear_progress() {
	clear_line
}

# Cleanup function for script exit
cleanup_on_exit() {
	# Clear sensitive password from memory
	if [[ -n "$SUDO_PASSWORD" ]]; then
		unset SUDO_PASSWORD
		verbose_log "Cleared sudo password from memory"
	fi
	
	# Clean up temporary directories
	if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
		rm -rf "$TEMP_DIR"
		verbose_log "Cleaned up temporary directory: $TEMP_DIR"
	fi
	
	# Clear all sensitive variables from environment
	unset BUNDLE_FILE BUNDLE_DIR SYSTEM_ARCH HELM_ARCH KUBECTL_ARCH
	unset CURRENT_STEP TOTAL_STEPS
	
	verbose_log "Cleared variables from memory"
}

# Set up cleanup trap
trap cleanup_on_exit EXIT

# Unified system architecture detection
detect_system_architecture() {
	SYSTEM_ARCH=$(uname -m)
	case "$SYSTEM_ARCH" in
		x86_64) HELM_ARCH="amd64"; KUBECTL_ARCH="amd64" ;;
		aarch64) HELM_ARCH="arm64"; KUBECTL_ARCH="arm64" ;;
		armv7l) HELM_ARCH="arm"; KUBECTL_ARCH="arm" ;;
		*) warn "Unknown architecture: $SYSTEM_ARCH. Using x86_64 defaults."
		   HELM_ARCH="amd64"; KUBECTL_ARCH="amd64" ;;
	esac
	verbose_log "Architecture detected: $SYSTEM_ARCH -> helm:$HELM_ARCH, kubectl:$KUBECTL_ARCH"
}

# Capture sudo password securely for single-prompt authentication
capture_sudo_password() {
	verbose_log "Requesting sudo authentication for installation"
	
	if [[ "$QUIET" != "true" ]]; then
		echo -e "${CYAN}${LOCK} This installation requires sudo access to install system binaries${NC}"
		echo -e "     ${BOLD}Locations:${NC} /usr/local/bin/, /usr/bin/ (symlinks)"
		echo ""
	fi
	
	# Capture password without echoing to terminal
	read -s -p "Enter sudo password: " SUDO_PASSWORD
	echo ""
	
	# Test sudo access immediately
	if ! echo "$SUDO_PASSWORD" | sudo -S -v 2>/dev/null; then
		error "Invalid sudo password or insufficient privileges"
	fi
	
	verbose_log "Sudo authentication successful"
}

# Pre-execution step setup (handles progress display and completion checking)
pre_execute_steps() {
	local step_name="$1"
	local step_description="$2"
	
	CURRENT_STEP=$((CURRENT_STEP + 1))
	
	# Calculate step prefix length for consistent alignment
	local step_prefix="[$CURRENT_STEP/$TOTAL_STEPS] "
	local prefix_length=${#step_prefix}
	
	# Display progress indicator
	if [[ "$QUIET" != "true" ]]; then
		# Calculate dots to align status indicators, accounting for status text length
		# Status text will be " ✅ Complete" or " ❌ Failed" (roughly 11 characters)
		local status_space=11
		local dots_needed=$((80 - prefix_length - ${#step_description} - status_space))
		if [[ $dots_needed -lt 3 ]]; then dots_needed=3; fi
		local dots=$(printf "%*s" $dots_needed "" | tr ' ' '.')
		printf "${CYAN}[%s/%s]${NC} %s%s" "$CURRENT_STEP" "$TOTAL_STEPS" "$step_description" "$dots"
	fi
	
	# For verbose mode, add newline before command output
	if [[ "$VERBOSE" == "true" ]] && [[ "$QUIET" != "true" ]]; then
		echo "" # New line for verbose mode
	fi
	
	return 0  # Signal to proceed with execution
}

# Post-execution step completion (handles success/failure marking and display)
post_execute_steps() {
	local step_name="$1"
	local exit_code="$2"
	local log_file="$3"
	
	if [[ $exit_code -eq 0 ]]; then
		if [[ "$VERBOSE" == "true" ]]; then
			[[ "$QUIET" != "true" ]] && echo -e "         ${CHECK} Complete"
		else
			[[ "$QUIET" != "true" ]] && echo -e " ${CHECK} Complete"
		fi
		[[ -n "$log_file" ]] && rm -f "$log_file"
		return 0
	else
		if [[ "$VERBOSE" == "true" ]]; then
			[[ "$QUIET" != "true" ]] && echo -e "         ${CROSS} Failed"
		else
			[[ "$QUIET" != "true" ]] && echo -e " ${CROSS} Failed"
			# Show error details for non-verbose mode with clear separation
			if [[ -n "$log_file" ]] && [[ -f "$log_file" ]]; then
				echo ""
				echo "   ${BOLD}Error details:${NC}"
				cat "$log_file" | head -10 | sed 's/^/   /'
				[[ $(wc -l < "$log_file" | tr -d '\n') -gt 10 ]] && echo "   ... (run with --verbose for full output)"
			fi
		fi
		[[ -n "$log_file" ]] && rm -f "$log_file"
		return 1
	fi
}

# Header display for main execution
show_header() {
	if [[ "$QUIET" == "true" ]]; then
		return
	fi

	echo ""
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}${CYAN}               K3S + AZURE ARC OFFLINE BUNDLE INSTALLER${NC}"
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""

	status "${PACKAGE} Installing offline installation bundle"
	echo -e "   ${BOLD}Bundle:${NC} $(basename "$BUNDLE_FILE")"
	echo -e "   ${BOLD}Architecture:${NC} $SYSTEM_ARCH"
	if [[ "$UPGRADE" == "true" ]]; then
		echo -e "   ${BOLD}Mode:${NC} Upgrade (overwrite existing)"
	else
		echo -e "   ${BOLD}Mode:${NC} Install"
	fi
	echo ""
}

# Usage function
usage() {
	echo -e "${BOLD}K3s + Azure Arc Offline Bundle Installer${NC}"
	echo ""
	echo -e "${BOLD}USAGE:${NC}"
	echo "    $0 [OPTIONS] BUNDLE_FILE"
	echo ""
	echo -e "${BOLD}DESCRIPTION:${NC}"
	echo "    Installs offline installation bundle components to system locations where"
	echo "    setup-k3s-arc.sh can detect and use them for offline deployments."
	echo ""
	echo -e "${BOLD}ARGUMENTS:${NC}"
	echo "    BUNDLE_FILE                 Path to offline installation bundle (.tar.gz)"
	echo ""
	echo -e "${BOLD}OPTIONS:${NC}"
	echo "    --upgrade                   Overwrite existing installations without prompting"
	echo "    --verbose                   Show detailed technical output"
	echo "    --quiet                     Minimal output (errors only)"
	echo "    --help                      Show this help message"
	echo ""
	echo -e "${BOLD}EXAMPLES:${NC}"
	echo "    # Install bundle components"
	echo "    $0 k3s-arc-offline-install-bundle-20250731.tar.gz"
	echo ""
	echo -e "    # Upgrade existing installation"
	echo "    $0 --upgrade k3s-arc-offline-install-bundle-20250731.tar.gz"
	echo ""
	echo -e "    # Install with detailed output"
	echo "    $0 --verbose k3s-arc-offline-install-bundle-20250731.tar.gz"
	echo ""
	echo -e "${BOLD}INSTALLATION LOCATIONS:${NC}"
	echo "    ${GEAR} Helm: /usr/local/bin/helm → /usr/bin/helm (symlink)"
	echo "    ${GEAR} kubectl: /usr/local/bin/kubectl → /usr/bin/kubectl (symlink)"
	echo "    ${GEAR} Azure CLI: ~/.k3s-arc-offline/azure-cli/ (user local)"
	echo "    ${GEAR} Completion marker: ~/.k3s-arc-offline/components-installed"
	echo ""
	echo -e "${BOLD}DETECTION:${NC}"
	echo "    setup-k3s-arc.sh --offline will automatically detect installed components"
	echo ""
	exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		--upgrade)
			UPGRADE=true
			shift
			;;
		--verbose)
			VERBOSE=true
			shift
			;;
		--quiet)
			QUIET=true
			shift
			;;
		--help)
			usage
			;;
		-*)
			error "Unknown option: $1"
			;;
		*)
			if [[ -z "$BUNDLE_FILE" ]]; then
				BUNDLE_FILE="$1"
			else
				error "Multiple bundle files specified. Only one bundle can be installed at a time."
			fi
			shift
			;;
	esac
done

# Validate required arguments
if [[ -z "$BUNDLE_FILE" ]]; then
	error "Bundle file argument required. Use --help for usage information."
fi

# Validate bundle file exists
if [[ ! -f "$BUNDLE_FILE" ]]; then
	error "Bundle file not found: $BUNDLE_FILE"
fi

# Validate bundle filename format
if [[ ! "$(basename "$BUNDLE_FILE")" =~ ^k3s-arc-offline-install-bundle-[0-9]{8}\.tar\.gz$ ]]; then
	error "Invalid bundle filename format. Expected: k3s-arc-offline-install-bundle-YYYYMMDD.tar.gz"
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as a regular user with sudo access."
fi

# Detect system architecture
detect_system_architecture

# Capture sudo password for single-prompt authentication
capture_sudo_password

# Show header
show_header

# Function to validate bundle checksum
validate_bundle_checksum() {
	local bundle_file="$1"
	local bundle_filename=$(basename "$bundle_file")
	
	verbose_log "Validating bundle checksum..."
	
	# Calculate actual checksum first
	local actual_checksum=$(sha256sum "$bundle_file" | cut -d' ' -f1)
	verbose_log "Calculated bundle checksum: $actual_checksum"
	
	# Try to get expected checksum from external manifest.md
	local expected_checksum=""
	local manifest_md_file="bundles/manifest.md"
	
	if [[ -f "$manifest_md_file" ]]; then
		verbose_log "Checking external manifest for checksum..."
		# Extract checksum from manifest.md table for this specific bundle
		expected_checksum=$(grep "| $bundle_filename |" "$manifest_md_file" | sed 's/.*| `\([^`]*\)` |.*/\1/' | head -1)
		if [[ -n "$expected_checksum" ]] && [[ "$expected_checksum" != "$bundle_filename"* ]]; then
			verbose_log "Found expected checksum in external manifest: $expected_checksum"
			
			# Compare checksums
			if [[ "$expected_checksum" != "$actual_checksum" ]]; then
				verbose_log "Checksum mismatch detected"
				verbose_log "Expected: $expected_checksum"
				verbose_log "Actual:   $actual_checksum"
				
				# Always prompt user for confirmation unless in quiet mode
				if [[ "$QUIET" != "true" ]]; then
					# Clear any pending progress dots first
					if [[ "$VERBOSE" != "true" ]]; then
						echo ""
					fi
					
					echo -e "${YELLOW}${WARN} Bundle checksum mismatch detected${NC}"
					echo -e "   ${BOLD}Expected:${NC} $expected_checksum"
					echo -e "   ${BOLD}Actual:${NC}   $actual_checksum"
					echo ""
					echo -e "This could indicate:"
					echo -e "   • Bundle was modified after creation"
					echo -e "   • Bundle was corrupted during transfer"
					echo -e "   • Bundle integrity compromised"
					echo ""
					
					# Prompt for confirmation
					while true; do
						read -p "Continue with installation anyway? [y/N]: " -n 1 -r
						echo ""
						case $REPLY in
							[Yy]* )
								verbose_log "User chose to proceed despite checksum mismatch"
								break
								;;
							[Nn]* | "" )
								verbose_log "User chose to abort due to checksum mismatch"
								return 1
								;;
							* )
								echo "Please answer y (yes) or n (no)."
								;;
						esac
					done
				else
					# In quiet mode, fail without prompting
					verbose_log "Checksum mismatch in quiet mode - failing without prompt"
					return 1
				fi
			else
				verbose_log "Bundle checksum validation passed"
			fi
		else
			verbose_log "Bundle entry not found in manifest"
		fi
	else
		verbose_log "No external manifest found"
		
		# No manifest found - report checksum and ask user to continue
		if [[ "$QUIET" != "true" ]]; then
			# Clear any pending progress dots first
			if [[ "$VERBOSE" != "true" ]]; then
				echo ""
			fi
			
			echo -e "${YELLOW}${WARN} No bundle manifest found for checksum validation${NC}"
			echo -e "   ${BOLD}Calculated checksum:${NC} $actual_checksum"
			echo ""
			echo -e "Without a manifest, bundle integrity cannot be verified."
			echo -e "The bundle may be legitimate but was not created with manifest tracking."
			echo ""
			
			# Prompt for confirmation
			while true; do
				read -p "Continue with installation anyway? [y/N]: " -n 1 -r
				echo ""
				case $REPLY in
					[Yy]* )
						verbose_log "User chose to proceed without checksum validation"
						break
						;;
					[Nn]* | "" )
						verbose_log "User chose to abort due to missing manifest"
						return 1
						;;
					* )
						echo "Please answer y (yes) or n (no)."
						;;
				esac
			done
		else
			# In quiet mode, fail without prompting when no manifest
			verbose_log "No manifest found in quiet mode - failing without prompt"
			return 1
		fi
	fi
	
	verbose_log "Bundle checksum validation completed successfully"
	return 0
}

# Function to extract bundle
extract_bundle() {
	local bundle_file="$1"
	
	verbose_log "Extracting bundle to temporary directory..."
	
	# Create temporary directory
	TEMP_DIR=$(mktemp -d)
	
	# Extract bundle
	if ! tar -xzf "$bundle_file" -C "$TEMP_DIR"; then
		return 1
	fi
	
	# Find bundle directory (should be only one)
	BUNDLE_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "k3s-arc-offline-install-bundle-*")
	if [[ -z "$BUNDLE_DIR" ]]; then
		return 1
	fi
	
	verbose_log "Bundle extracted to: $BUNDLE_DIR"
	return 0
}

# Function to install Helm binary
install_helm() {
	local bundle_dir="$1"
	
	verbose_log "Installing Helm binary for architecture: $HELM_ARCH"
	
	local helm_archive="$bundle_dir/binaries/helm-v3.12.2-linux-${HELM_ARCH}.tar.gz"
	if [[ ! -f "$helm_archive" ]]; then
		verbose_log "Helm archive not found: $helm_archive"
		return 1
	fi
	
	# Create temporary extraction directory
	local temp_helm_dir=$(mktemp -d)
	
	# Extract Helm
	if ! tar -xzf "$helm_archive" -C "$temp_helm_dir"; then
		rm -rf "$temp_helm_dir"
		return 1
	fi
	
	# Find helm binary
	local helm_binary=$(find "$temp_helm_dir" -name "helm" -type f)
	if [[ -z "$helm_binary" ]]; then
		rm -rf "$temp_helm_dir"
		return 1
	fi
	
	# Install to system location
	if ! echo "$SUDO_PASSWORD" | sudo -S cp "$helm_binary" /usr/local/bin/helm; then
		rm -rf "$temp_helm_dir"
		return 1
	fi
	
	if ! echo "$SUDO_PASSWORD" | sudo -S chmod +x /usr/local/bin/helm; then
		rm -rf "$temp_helm_dir"
		return 1
	fi
	
	# Create symlink if it doesn't exist or if upgrading
	if [[ "$UPGRADE" == "true" ]] || [[ ! -L /usr/bin/helm ]]; then
		echo "$SUDO_PASSWORD" | sudo -S ln -sf /usr/local/bin/helm /usr/bin/helm
	fi
	
	rm -rf "$temp_helm_dir"
	verbose_log "Helm installed successfully"
	return 0
}

# Function to install kubectl binary
install_kubectl() {
	local bundle_dir="$1"
	
	verbose_log "Installing kubectl binary for architecture: $KUBECTL_ARCH"
	
	local kubectl_binary="$bundle_dir/binaries/kubectl-${KUBECTL_ARCH}"
	if [[ ! -f "$kubectl_binary" ]]; then
		verbose_log "kubectl binary not found: $kubectl_binary"
		return 1
	fi
	
	# Install to system location
	if ! echo "$SUDO_PASSWORD" | sudo -S cp "$kubectl_binary" /usr/local/bin/kubectl; then
		return 1
	fi
	
	if ! echo "$SUDO_PASSWORD" | sudo -S chmod +x /usr/local/bin/kubectl; then
		return 1
	fi
	
	# Create symlink if it doesn't exist or if upgrading
	if [[ "$UPGRADE" == "true" ]] || [[ ! -L /usr/bin/kubectl ]]; then
		echo "$SUDO_PASSWORD" | sudo -S ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
	fi
	
	verbose_log "kubectl installed successfully"
	return 0
}

# Function to install Azure CLI wheels
install_azure_cli() {
	local bundle_dir="$1"
	
	verbose_log "Installing Azure CLI wheels to user directory..."
	
	# Check if pip3 is available
	if ! command -v pip3 >/dev/null 2>&1; then
		verbose_log "pip3 not found - attempting to install python3-pip"
		
		# Try to install pip3 using the system package manager
		if command -v dnf >/dev/null 2>&1; then
			verbose_log "Installing python3-pip using dnf..."
			if ! echo "$SUDO_PASSWORD" | sudo -S dnf install -y python3-pip >/dev/null 2>&1; then
				verbose_log "Failed to install python3-pip with dnf"
				return 1
			fi
		elif command -v yum >/dev/null 2>&1; then
			verbose_log "Installing python3-pip using yum..."
			if ! echo "$SUDO_PASSWORD" | sudo -S yum install -y python3-pip >/dev/null 2>&1; then
				verbose_log "Failed to install python3-pip with yum"
				return 1
			fi
		elif command -v apt-get >/dev/null 2>&1; then
			verbose_log "Installing python3-pip using apt-get..."
			if ! echo "$SUDO_PASSWORD" | sudo -S apt-get update >/dev/null 2>&1 || \
			   ! echo "$SUDO_PASSWORD" | sudo -S apt-get install -y python3-pip >/dev/null 2>&1; then
				verbose_log "Failed to install python3-pip with apt-get"
				return 1
			fi
		else
			verbose_log "No supported package manager found (dnf, yum, apt-get)"
			return 1
		fi
		
		# Verify pip3 is now available
		if ! command -v pip3 >/dev/null 2>&1; then
			verbose_log "pip3 still not available after installation attempt"
			return 1
		fi
		
		verbose_log "Successfully installed pip3"
	fi
	
	local wheels_dir="$bundle_dir/azure-cli/wheels"
	if [[ ! -d "$wheels_dir" ]] || [[ $(ls "$wheels_dir"/*.whl 2>/dev/null | wc -l) -eq 0 ]]; then
		verbose_log "Azure CLI wheels not found in: $wheels_dir"
		return 1
	fi
	
	# Create offline directory structure
	mkdir -p "$AZURE_CLI_DIR"
	
	# Copy wheels to user's offline directory
	if ! cp -r "$wheels_dir" "$AZURE_CLI_DIR/"; then
		verbose_log "Failed to copy wheels to $AZURE_CLI_DIR"
		return 1
	fi
	
	# Install Azure CLI from local wheels with better error handling
	verbose_log "Installing Azure CLI from wheels..."
	local pip_output
	if ! pip_output=$(pip3 install --user --no-index --find-links "$AZURE_CLI_DIR/wheels" azure-cli 2>&1); then
		verbose_log "pip3 offline installation failed with output: $pip_output"
		
		# Check if failure is due to missing architecture-specific wheels
		if echo "$pip_output" | grep -q "Could not find a version that satisfies the requirement" || \
		   echo "$pip_output" | grep -q "No matching distribution found"; then
			verbose_log "Detected missing architecture-specific wheels, attempting hybrid installation..."
			
			# Try hybrid approach: use local wheels where available, online for missing ones
			if ! pip_output=$(pip3 install --user --find-links "$AZURE_CLI_DIR/wheels" azure-cli 2>&1); then
				verbose_log "Hybrid installation also failed: $pip_output"
				return 1
			else
				verbose_log "Successfully installed Azure CLI using hybrid approach (local + online wheels)"
			fi
		else
			verbose_log "Installation failed for reasons other than missing wheels"
			return 1
		fi
	fi
	
	# Verify Azure CLI was installed
	if ! command -v az >/dev/null 2>&1; then
		# Try to find az in the expected location
		if [[ -f "$HOME/.local/bin/az" ]]; then
			verbose_log "Azure CLI installed but not in PATH - will be available after PATH update"
		else
			verbose_log "Azure CLI installation verification failed - az command not found"
			return 1
		fi
	fi
	
	# Add to PATH if not already there
	if ! grep -q "export PATH=\"\$HOME/.local/bin:\$PATH\"" ~/.bashrc 2>/dev/null; then
		echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
		verbose_log "Added ~/.local/bin to PATH in ~/.bashrc"
	fi
	
	verbose_log "Azure CLI installed successfully from wheels"
	return 0
}

# Function to create completion markers
create_completion_markers() {
	verbose_log "Creating installation completion markers..."
	
	# Create offline base directory
	mkdir -p "$OFFLINE_BASE_DIR"
	
	# Create completion marker with metadata
	cat > "$COMPLETION_MARKER" << EOF
# K3s Arc Offline Components Installation Marker
# Generated by install-k3s-arc-offline-install-bundle.sh

INSTALLATION_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BUNDLE_FILE=$(basename "$BUNDLE_FILE")
SYSTEM_ARCHITECTURE=$SYSTEM_ARCH
COMPONENTS_INSTALLED=helm,kubectl,azure-cli

# Component locations
HELM_LOCATION=/usr/local/bin/helm
KUBECTL_LOCATION=/usr/local/bin/kubectl
AZURE_CLI_LOCATION=$HOME/.local/bin/az
AZURE_CLI_WHEELS=$AZURE_CLI_DIR/wheels

# Detection status
HELM_INSTALLED=true
KUBECTL_INSTALLED=true
AZURE_CLI_INSTALLED=true
EOF
	
	verbose_log "Created completion marker: $COMPLETION_MARKER"
	return 0
}

# Function to verify installation
verify_installation() {
	verbose_log "Verifying component installation..."
	
	# Check Helm
	if ! command -v helm >/dev/null 2>&1; then
		verbose_log "Helm verification failed - command not found"
		return 1
	fi
	
	# Check kubectl
	if ! command -v kubectl >/dev/null 2>&1; then
		verbose_log "kubectl verification failed - command not found"
		return 1
	fi
	
	# Check Azure CLI
	if ! command -v az >/dev/null 2>&1; then
		verbose_log "Azure CLI verification failed - command not found"
		return 1
	fi
	
	# Check completion marker
	if [[ ! -f "$COMPLETION_MARKER" ]]; then
		verbose_log "Completion marker not found"
		return 1
	fi
	
	verbose_log "All components verified successfully"
	return 0
}

# Main execution logic
TOTAL_STEPS=6
CURRENT_STEP=0

# Step 1: Validate bundle checksum
if pre_execute_steps "validate_checksum" "Validating bundle integrity"; then
	if [[ "$VERBOSE" == "true" ]]; then
		validate_bundle_checksum "$BUNDLE_FILE"
		exit_code=$?
	else
		# Don't redirect user interaction to log file - only technical output
		validate_bundle_checksum "$BUNDLE_FILE"
		exit_code=$?
	fi
	
	if ! post_execute_steps "validate_checksum" "$exit_code" ""; then
		error "Bundle checksum validation failed. Bundle may be corrupted."
	fi
fi

# Step 2: Extract bundle
if pre_execute_steps "extract_bundle" "Extracting bundle contents"; then
	if [[ "$VERBOSE" == "true" ]]; then
		extract_bundle "$BUNDLE_FILE"
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-install-$$.log"
		extract_bundle "$BUNDLE_FILE" >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "extract_bundle" "$exit_code" "$log_file"; then
		error "Failed to extract bundle contents"
	fi
fi

# Step 3: Install Helm
if pre_execute_steps "install_helm" "Installing Helm binary"; then
	if [[ "$VERBOSE" == "true" ]]; then
		install_helm "$BUNDLE_DIR"
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-install-$$.log"
		install_helm "$BUNDLE_DIR" >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "install_helm" "$exit_code" "$log_file"; then
		error "Failed to install Helm binary"
	fi
fi

# Step 4: Install kubectl
if pre_execute_steps "install_kubectl" "Installing kubectl binary"; then
	if [[ "$VERBOSE" == "true" ]]; then
		install_kubectl "$BUNDLE_DIR"
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-install-$$.log"
		install_kubectl "$BUNDLE_DIR" >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "install_kubectl" "$exit_code" "$log_file"; then
		error "Failed to install kubectl binary"
	fi
fi

# Step 5: Install Azure CLI
if pre_execute_steps "install_azure_cli" "Installing Azure CLI from wheels"; then
	if [[ "$VERBOSE" == "true" ]]; then
		install_azure_cli "$BUNDLE_DIR"
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-install-$$.log"
		install_azure_cli "$BUNDLE_DIR" >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "install_azure_cli" "$exit_code" "$log_file"; then
		error "Failed to install Azure CLI from wheels"
	fi
fi

# Step 6: Create completion markers and verify
if pre_execute_steps "finalize_installation" "Creating completion markers"; then
	if [[ "$VERBOSE" == "true" ]]; then
		create_completion_markers && verify_installation
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-install-$$.log"
		(create_completion_markers && verify_installation) >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "finalize_installation" "$exit_code" "$log_file"; then
		error "Failed to finalize installation"
	fi
fi

# Get component versions for display
helm_version=$(helm version --short 2>/dev/null | head -1 || echo "installed")
kubectl_version=$(kubectl version --client 2>/dev/null | grep -o 'v[0-9][0-9.]*' | head -1 || echo "installed")
az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "installed")

# Show completion message
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${CYAN}                   INSTALLATION COMPLETED SUCCESSFULLY${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
success "Offline components installed successfully"
echo -e "   ${BOLD}Bundle:${NC} $(basename "$BUNDLE_FILE")"
echo -e "   ${BOLD}Architecture:${NC} $SYSTEM_ARCH"
echo -e "   ${BOLD}Completion marker:${NC} $COMPLETION_MARKER"
echo ""
echo -e "${BOLD}INSTALLED COMPONENTS:${NC}"
echo "   ${GEAR} Helm: $helm_version"
echo "   ${GEAR} kubectl: $kubectl_version"
echo "   ${GEAR} Azure CLI: $az_version"
echo ""
echo -e "${BOLD}INSTALLATION LOCATIONS:${NC}"
echo "   ${GEAR} Helm: /usr/local/bin/helm → /usr/bin/helm"
echo "   ${GEAR} kubectl: /usr/local/bin/kubectl → /usr/bin/kubectl"
echo "   ${GEAR} Azure CLI: ~/.local/bin/az (wheels: $AZURE_CLI_DIR/wheels)"
echo ""
echo -e "${BOLD}NEXT STEPS:${NC}"
info "Restart your shell or run: source ~/.bashrc"
info "Verify components: helm version && kubectl version --client && az version"
info "Use offline mode: ./setup-k3s-arc.sh --offline [other-options]"
echo ""
echo -e "${BOLD}DETECTION STATUS:${NC}"
echo "   ${CHECK} setup-k3s-arc.sh --offline will automatically detect these components"
echo "   ${CHECK} Components can be used immediately for offline deployments"
echo ""

# Cleanup handled by cleanup_on_exit trap