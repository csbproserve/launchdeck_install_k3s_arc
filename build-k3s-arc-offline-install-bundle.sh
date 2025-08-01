#!/bin/bash
# 2025.07.30 - CSB Dev <csbdev@cspire.com>
#
# K3s + Azure Arc Offline Installation Bundle Builder
# This script creates offline installation bundles for K3s + Azure Arc setup
#
# Usage: ./build-k3s-arc-offline-install-bundle.sh [OPTIONS]

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

# Secure sudo password storage (memory only)
SUDO_PASSWORD=""

# Output mode control
VERBOSE=false
QUIET=false

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
	unset BUNDLE_NAME BUNDLE_DIR SYSTEM_ARCH HELM_ARCH KUBECTL_ARCH
	unset CURRENT_STEP TOTAL_STEPS HELM_VERSION KUBECTL_VERSION
	unset bundle_file bundle_size bundle_checksum
	
	verbose_log "Cleared variables from memory"
}

# Set up cleanup trap
trap cleanup_on_exit EXIT

# Unified system architecture detection
detect_system_architecture() {
	SYSTEM_ARCH=$(uname -m)
	case "$SYSTEM_ARCH" in
		x86_64) HELM_ARCH="amd64"; KUBECTL_ARCH="amd64" ;;
		aarch64|arm64) HELM_ARCH="arm64"; KUBECTL_ARCH="arm64" ;;
		armv7l) HELM_ARCH="arm"; KUBECTL_ARCH="arm" ;;
		*) warn "Unknown architecture: $SYSTEM_ARCH. Using x86_64 defaults."
		   HELM_ARCH="amd64"; KUBECTL_ARCH="amd64" ;;
	esac
	verbose_log "Architecture detected: $SYSTEM_ARCH -> helm:$HELM_ARCH, kubectl:$KUBECTL_ARCH"
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
	echo -e "${BOLD}${CYAN}               K3S + AZURE ARC OFFLINE BUNDLE BUILDER${NC}"
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""

	if [[ "$REMOVE_BUNDLE" != "" ]]; then
		status "${WRENCH} Removing offline installation bundle"
		echo -e "   ${BOLD}Bundle:${NC} ${REMOVE_BUNDLE}"
	else
		status "${PACKAGE} Building offline installation bundle"
		echo -e "   ${BOLD}Bundle:${NC} ${BUNDLE_NAME}"
		echo -e "   ${BOLD}Architecture:${NC} Multi-arch (amd64, arm64)"
		echo -e "   ${BOLD}Components:${NC} Helm, kubectl, Azure CLI, K3s installer"
	fi
	echo ""
}

# Usage function
usage() {
	echo -e "${BOLD}K3s + Azure Arc Offline Bundle Builder${NC}"
	echo ""
	echo -e "${BOLD}USAGE:${NC}"
	echo "    $0 [OPTIONS]"
	echo ""
	echo -e "${BOLD}DESCRIPTION:${NC}"
	echo "    Creates offline installation bundles containing Helm, kubectl, Azure CLI wheels,"
	echo "    and K3s installer script. Reduces bandwidth requirements for K3s + Arc deployments."
	echo ""
	echo -e "${BOLD}OPTIONS:${NC}"
	echo "    --remove-bundle FILENAME    Remove specified bundle and update manifest"
	echo "    --verbose                   Show detailed technical output"
	echo "    --quiet                     Minimal output (errors only)"
	echo "    --help                      Show this help message"
	echo ""
	echo -e "${BOLD}EXAMPLES:${NC}"
	echo "    # Build new offline bundle"
	echo "    $0"
	echo ""
	echo "    # Build with detailed output"
	echo "    $0 --verbose"
	echo ""
	echo "    # Remove existing bundle"
	echo "    $0 --remove-bundle k3s-arc-offline-install-bundle-20250730.tar.gz"
	echo ""
	echo -e "${BOLD}BUNDLE CONTENTS:${NC}"
	echo "    ${GEAR} Helm v3.12.2 (amd64, arm64)"
	echo "    ${GEAR} kubectl (latest stable, amd64, arm64)"
	echo "    ${GEAR} Azure CLI Python wheels (complete dependency tree)"
	echo "    ${GEAR} Fresh K3s installation script from get.k3s.io"
	echo "    ${GEAR} Component installation helper scripts"
	echo "    ${GEAR} Bundle manifest with metadata and checksums"
	echo ""
	echo -e "${BOLD}OUTPUT:${NC}"
	echo "    Bundle saved to: ${BOLD}bundles/k3s-arc-offline-install-bundle-YYYYMMDD.tar.gz${NC}"
	echo "    Manifest updated: ${BOLD}bundles/manifest.md${NC}"
	echo ""
	echo -e "${BOLD}BANDWIDTH SAVINGS:${NC}"
	echo "    ${GEAR} Helm: ~30MB (both architectures)"
	echo "    ${GEAR} kubectl: ~90MB (both architectures)"
	echo "    ${GEAR} Azure CLI: ~180MB+ (with dependencies)"
	echo "    ${GEAR} Total: ~300MB+ per installation avoided"
	echo ""
	exit 1
}

# Parse command line arguments
REMOVE_BUNDLE=""

while [[ $# -gt 0 ]]; do
	case $1 in
		--remove-bundle)
			REMOVE_BUNDLE="$2"
			shift 2
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
		*)
			error "Unknown parameter: $1"
			;;
	esac
done

# Validate bundle removal parameter
if [[ -n "$REMOVE_BUNDLE" ]] && [[ ! "$REMOVE_BUNDLE" =~ ^k3s-arc-offline-install-bundle-[0-9]{8}\.tar\.gz$ ]]; then
	error "Invalid bundle filename format. Expected: k3s-arc-offline-install-bundle-YYYYMMDD.tar.gz"
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as a regular user."
fi

# Detect system architecture
detect_system_architecture

# Set bundle name with current date
BUNDLE_NAME="k3s-arc-offline-install-bundle-$(date +%Y%m%d)"
BUNDLE_DIR=""
TEMP_DIR=""

# Show header
show_header

# Function to download Helm binaries
download_helm_binaries() {
	local bundle_dir="$1"
	local binaries_dir="$bundle_dir/binaries"
	
	mkdir -p "$binaries_dir"
	
	verbose_log "Downloading Helm v3.12.2 for multiple architectures..."
	
	# Download AMD64 version
	local helm_amd64_url="https://get.helm.sh/helm-v3.12.2-linux-amd64.tar.gz"
	if ! curl -fsSL "$helm_amd64_url" -o "$binaries_dir/helm-v3.12.2-linux-amd64.tar.gz"; then
		return 1
	fi
	verbose_log "Downloaded Helm amd64: helm-v3.12.2-linux-amd64.tar.gz"
	
	# Download ARM64 version
	local helm_arm64_url="https://get.helm.sh/helm-v3.12.2-linux-arm64.tar.gz"
	if ! curl -fsSL "$helm_arm64_url" -o "$binaries_dir/helm-v3.12.2-linux-arm64.tar.gz"; then
		return 1
	fi
	verbose_log "Downloaded Helm arm64: helm-v3.12.2-linux-arm64.tar.gz"
	
	# Verify downloads
	if [[ ! -f "$binaries_dir/helm-v3.12.2-linux-amd64.tar.gz" ]] || [[ ! -f "$binaries_dir/helm-v3.12.2-linux-arm64.tar.gz" ]]; then
		return 1
	fi
	
	return 0
}

# Function to download kubectl binaries
download_kubectl_binaries() {
	local bundle_dir="$1"
	local binaries_dir="$bundle_dir/binaries"
	
	mkdir -p "$binaries_dir"
	
	verbose_log "Getting latest kubectl version..."
	KUBECTL_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
	if [[ -z "$KUBECTL_VERSION" ]]; then
		error "Failed to get kubectl version information"
		return 1
	fi
	verbose_log "Latest kubectl version: $KUBECTL_VERSION"
	
	# Download AMD64 version
	local kubectl_amd64_url="https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
	if ! curl -fsSL "$kubectl_amd64_url" -o "$binaries_dir/kubectl-amd64"; then
		return 1
	fi
	chmod +x "$binaries_dir/kubectl-amd64"
	verbose_log "Downloaded kubectl amd64: kubectl-amd64"
	
	# Download ARM64 version
	local kubectl_arm64_url="https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl"
	if ! curl -fsSL "$kubectl_arm64_url" -o "$binaries_dir/kubectl-arm64"; then
		return 1
	fi
	chmod +x "$binaries_dir/kubectl-arm64"
	verbose_log "Downloaded kubectl arm64: kubectl-arm64"
	
	# Verify downloads
	if [[ ! -f "$binaries_dir/kubectl-amd64" ]] || [[ ! -f "$binaries_dir/kubectl-arm64" ]]; then
		return 1
	fi
	
	return 0
}

# Function to download Azure CLI wheels
download_azure_cli_wheels() {
	local bundle_dir="$1"
	local azure_dir="$bundle_dir/azure-cli"
	local wheels_dir="$azure_dir/wheels"
	
	mkdir -p "$wheels_dir"
	
	verbose_log "Downloading Azure CLI wheels and dependencies..."
	
	# Create temporary directory for pip download
	local temp_wheels_dir=$(mktemp -d)
	
	# Download azure-cli and all dependencies as wheels
	if ! pip3 download azure-cli --dest "$temp_wheels_dir" --quiet; then
		rm -rf "$temp_wheels_dir"
		return 1
	fi
	
	# Move downloaded wheels to bundle directory
	if ! mv "$temp_wheels_dir"/*.whl "$wheels_dir/"; then
		rm -rf "$temp_wheels_dir"
		return 1
	fi
	
	rm -rf "$temp_wheels_dir"
	
	# Count downloaded wheels
	local wheel_count=$(ls "$wheels_dir"/*.whl 2>/dev/null | wc -l)
	verbose_log "Downloaded $wheel_count Azure CLI wheels"
	
	if [[ $wheel_count -eq 0 ]]; then
		return 1
	fi
	
	return 0
}

# Function to download K3s installation script
download_k3s_script() {
	local bundle_dir="$1"
	local scripts_dir="$bundle_dir/scripts"
	
	mkdir -p "$scripts_dir"
	
	verbose_log "Downloading fresh K3s installation script..."
	
	if ! curl -fsSL https://get.k3s.io -o "$scripts_dir/k3s-install.sh"; then
		return 1
	fi
	
	chmod +x "$scripts_dir/k3s-install.sh"
	verbose_log "Downloaded K3s installer: k3s-install.sh"
	
	return 0
}

# Function to generate component installation script
generate_install_script() {
	local bundle_dir="$1"
	local scripts_dir="$bundle_dir/scripts"
	
	mkdir -p "$scripts_dir"
	
	verbose_log "Generating component installation script..."
	
	cat > "$scripts_dir/install-components.sh" << 'EOF'
#!/bin/bash
# K3s + Azure Arc Offline Component Installer
# Generated by build-k3s-arc-offline-install-bundle.sh

set -e

# Status glyphs for consistent display
CHECK="✅"
CROSS="❌"
GEAR="⚙️"

# Detect system architecture
SYSTEM_ARCH=$(uname -m)
case "$SYSTEM_ARCH" in
    x86_64) ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    armv7l) ARCH_SUFFIX="arm" ;;
    *) echo "Unsupported architecture: $SYSTEM_ARCH"; exit 1 ;;
esac

echo "Installing offline components for architecture: $SYSTEM_ARCH"

# Install Helm
echo "Installing Helm..."
HELM_TAR="binaries/helm-v3.12.2-linux-${ARCH_SUFFIX}.tar.gz"
if [[ -f "$HELM_TAR" ]]; then
    tar -zxf "$HELM_TAR" -C /tmp/
    sudo mv "/tmp/linux-${ARCH_SUFFIX}/helm" /usr/local/bin/helm
    sudo chmod +x /usr/local/bin/helm
    sudo ln -sf /usr/local/bin/helm /usr/bin/helm
    echo "${CHECK} Helm installed"
else
    echo "${CROSS} Helm binary not found for $SYSTEM_ARCH"
    exit 1
fi

# Install kubectl
echo "Installing kubectl..."
KUBECTL_BIN="binaries/kubectl-${ARCH_SUFFIX}"
if [[ -f "$KUBECTL_BIN" ]]; then
    sudo cp "$KUBECTL_BIN" /usr/local/bin/kubectl
    sudo chmod +x /usr/local/bin/kubectl
    sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
    echo "${CHECK} kubectl installed"
else
    echo "${CROSS} kubectl binary not found for $SYSTEM_ARCH"
    exit 1
fi

# Install Azure CLI from wheels
echo "Installing Azure CLI from wheels..."
if [[ -d "azure-cli/wheels" ]] && [[ $(ls azure-cli/wheels/*.whl 2>/dev/null | wc -l) -gt 0 ]]; then
    pip3 install --user --no-index --find-links azure-cli/wheels azure-cli
    # Add to PATH if not already there
    if ! grep -q "export PATH=\"\$HOME/.local/bin:\$PATH\"" ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
    export PATH="$HOME/.local/bin:$PATH"
    echo "${CHECK} Azure CLI installed"
else
    echo "${CROSS} Azure CLI wheels not found"
    exit 1
fi

echo ""
echo "${CHECK} All offline components installed successfully!"
echo "Components installed:"
echo "  ${GEAR} Helm: $(helm version --short 2>/dev/null || echo 'installed')"
echo "  ${GEAR} kubectl: $(kubectl version --client 2>/dev/null | grep -o 'v[0-9][0-9.]*' | head -1 || echo 'installed')"
echo "  ${GEAR} Azure CLI: $(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo 'installed')"
echo ""
echo "Note: You may need to restart your shell or run 'source ~/.bashrc' to update PATH"
EOF

	chmod +x "$scripts_dir/install-components.sh"
	verbose_log "Generated component installer: install-components.sh"
	
	return 0
}

# Function to create bundle manifest
create_manifest() {
	local bundle_dir="$1"
	local bundle_name="$2"
	
	verbose_log "Creating bundle manifest..."
	
	# Count Azure CLI wheels
	local wheel_count=0
	if [[ -d "$bundle_dir/azure-cli/wheels" ]]; then
		wheel_count=$(ls "$bundle_dir/azure-cli/wheels"/*.whl 2>/dev/null | wc -l)
	fi
	
	# Create manifest JSON
	cat > "$bundle_dir/manifest.json" << EOF
{
  "bundle_name": "$bundle_name",
  "created_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "created_by": "build-k3s-arc-offline-install-bundle.sh",
  "version": "1.0",
  "description": "Offline installation bundle for K3s + Azure Arc setup",
  "components": {
    "helm": {
      "version": "v3.12.2",
      "architectures": ["amd64", "arm64"],
      "source": "https://get.helm.sh/",
      "files": [
        "binaries/helm-v3.12.2-linux-amd64.tar.gz",
        "binaries/helm-v3.12.2-linux-arm64.tar.gz"
      ]
    },
    "kubectl": {
      "version": "$KUBECTL_VERSION",
      "architectures": ["amd64", "arm64"],
      "source": "https://storage.googleapis.com/kubernetes-release/",
      "files": [
        "binaries/kubectl-amd64",
        "binaries/kubectl-arm64"
      ]
    },
    "azure_cli": {
      "method": "pip_wheels",
      "wheel_count": $wheel_count,
      "source": "PyPI via pip3 download",
      "directory": "azure-cli/wheels/"
    },
    "k3s_installer": {
      "source": "https://get.k3s.io",
      "download_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "file": "scripts/k3s-install.sh"
    },
    "install_helper": {
      "description": "Component installation helper script",
      "file": "scripts/install-components.sh"
    }
  },
  "bundle_size": "TBD",
  "bundle_checksum": "TBD",
  "checksum_algorithm": "SHA256"
}
EOF

	verbose_log "Created manifest.json with component metadata"
	return 0
}

# Function to create bundle tarball with checksum
create_bundle_tarball() {
	local bundle_dir="$1"
	local bundle_name="$2"
	local output_file="bundles/${bundle_name}.tar.gz"
	
	verbose_log "Creating compressed bundle archive..."
	
	# Ensure bundles directory exists
	mkdir -p bundles
	
	# Update manifest with bundle size only (no checksum to avoid circular dependency)
	local temp_manifest=$(mktemp)
	jq --arg size "TBD" '.bundle_size = $size | .bundle_checksum = null' \
		"$bundle_dir/manifest.json" > "$temp_manifest"
	
	if ! mv "$temp_manifest" "$bundle_dir/manifest.json"; then
		rm -f "$temp_manifest"
		return 1
	fi
	
	# Create final tarball
	if ! tar -czf "$output_file" -C "$(dirname "$bundle_dir")" "$(basename "$bundle_dir")"; then
		return 1
	fi
	
	# Calculate final bundle size and checksum
	local bundle_size=$(du -h "$output_file" | cut -f1)
	local bundle_checksum=$(sha256sum "$output_file" | cut -d' ' -f1)
	
	verbose_log "Bundle size: $bundle_size"
	verbose_log "Bundle checksum: sha256:$bundle_checksum"
	verbose_log "Created bundle: $output_file"
	
	# Store checksum externally for validation (avoid circular dependency)
	export FINAL_BUNDLE_SIZE="$bundle_size"
	export FINAL_BUNDLE_CHECKSUM="$bundle_checksum"
	
	return 0
}

# Function to update bundles/manifest.md
update_bundle_manifest_file() {
	local bundle_name="$1"
	local bundle_file="bundles/${bundle_name}.tar.gz"
	
	verbose_log "Updating bundles/manifest.md with checksum..."
	
	if [[ ! -f "$bundle_file" ]]; then
		return 1
	fi
	
	# Get bundle information (use exported values from create_bundle_tarball)
	local bundle_size="${FINAL_BUNDLE_SIZE:-$(du -h "$bundle_file" | cut -f1)}"
	local bundle_checksum="${FINAL_BUNDLE_CHECKSUM:-$(sha256sum "$bundle_file" | cut -d' ' -f1)}"
	local bundle_date=$(date +%Y-%m-%d)
	
	# Read current manifest
	local manifest_file="bundles/manifest.md"
	if [[ ! -f "$manifest_file" ]]; then
		error "Bundle manifest file not found: $manifest_file"
		return 1
	fi
	
	# Create temporary file for updates
	local temp_manifest=$(mktemp)
	
	# Update the manifest with checksum information
	awk -v bundle_name="$bundle_name" -v bundle_size="$bundle_size" -v bundle_date="$bundle_date" -v bundle_checksum="$bundle_checksum" '
	/^## Available Bundles/ {
		print $0
		print ""
		if (getline && $0 == "*No bundles created yet. Use `build-k3s-arc-offline-install-bundle.sh` to create your first bundle.*") {
			print "| Bundle Name | Size | Created | Checksum | Description |"
			print "|-------------|------|---------|----------|-------------|"
			print "| " bundle_name ".tar.gz | " bundle_size " | " bundle_date " | `" bundle_checksum "` | Multi-arch offline installation bundle |"
		} else {
			print $0
			print "| " bundle_name ".tar.gz | " bundle_size " | " bundle_date " | `" bundle_checksum "` | Multi-arch offline installation bundle |"
		}
		next
	}
	{ print $0 }
	' "$manifest_file" > "$temp_manifest"
	
	if ! mv "$temp_manifest" "$manifest_file"; then
		rm -f "$temp_manifest"
		return 1
	fi
	
	verbose_log "Updated bundles/manifest.md with bundle entry and checksum"
	return 0
}

# Function to remove bundle
remove_bundle() {
	local bundle_name="$1"
	local bundle_file="bundles/$bundle_name"
	
	verbose_log "Removing bundle: $bundle_name"
	
	# Check if bundle exists
	if [[ ! -f "$bundle_file" ]]; then
		error "Bundle not found: $bundle_file"
		return 1
	fi
	
	# Remove bundle file
	if ! rm -f "$bundle_file"; then
		return 1
	fi
	
	verbose_log "Removed bundle file: $bundle_file"
	
	# Update manifest.md by removing the bundle entry
	local manifest_file="bundles/manifest.md"
	if [[ -f "$manifest_file" ]]; then
		local temp_manifest=$(mktemp)
		grep -v "$bundle_name" "$manifest_file" > "$temp_manifest"
		
		if ! mv "$temp_manifest" "$manifest_file"; then
			rm -f "$temp_manifest"
			return 1
		fi
		
		verbose_log "Updated bundles/manifest.md to remove bundle entry"
	fi
	
	return 0
}

# Main execution logic
if [[ -n "$REMOVE_BUNDLE" ]]; then
	# Bundle removal mode
	TOTAL_STEPS=3
	CURRENT_STEP=0
	
	# Step 1: Validate bundle
	if pre_execute_steps "validate_bundle" "Validating bundle path"; then
		if [[ "$VERBOSE" == "true" ]]; then
			echo "Checking if bundle exists: bundles/$REMOVE_BUNDLE"
			[[ -f "bundles/$REMOVE_BUNDLE" ]]
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			{
				echo "Checking if bundle exists: bundles/$REMOVE_BUNDLE"
				[[ -f "bundles/$REMOVE_BUNDLE" ]]
			} >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "validate_bundle" "$exit_code" "$log_file"; then
			error "Bundle not found: bundles/$REMOVE_BUNDLE"
		fi
	fi
	
	# Step 2: Remove bundle
	if pre_execute_steps "remove_bundle" "Removing bundle files"; then
		if [[ "$VERBOSE" == "true" ]]; then
			remove_bundle "$REMOVE_BUNDLE"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			remove_bundle "$REMOVE_BUNDLE" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "remove_bundle" "$exit_code" "$log_file"; then
			error "Failed to remove bundle: $REMOVE_BUNDLE"
		fi
	fi
	
	# Step 3: Update manifest
	if pre_execute_steps "update_manifest" "Updating bundle manifest"; then
		if [[ "$VERBOSE" == "true" ]]; then
			echo "Bundle manifest updated"
			exit_code=0
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			echo "Bundle manifest updated" >"$log_file" 2>&1
			exit_code=0
		fi
		
		if ! post_execute_steps "update_manifest" "$exit_code" "$log_file"; then
			error "Failed to update bundle manifest"
		fi
	fi
	
	# Show completion message
	echo ""
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}${CYAN}                         BUNDLE REMOVED${NC}"
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	success "Bundle successfully removed: $REMOVE_BUNDLE"
	echo -e "   ${BOLD}Manifest updated:${NC} bundles/manifest.md"
	echo ""
	
else
	# Bundle creation mode
	TOTAL_STEPS=8
	CURRENT_STEP=0
	
	# Create temporary directory for bundle creation
	TEMP_DIR=$(mktemp -d)
	BUNDLE_DIR="$TEMP_DIR/$BUNDLE_NAME"
	mkdir -p "$BUNDLE_DIR"
	
	# Step 1: Download Helm binaries
	if pre_execute_steps "download_helm" "Downloading Helm binaries"; then
		if [[ "$VERBOSE" == "true" ]]; then
			download_helm_binaries "$BUNDLE_DIR"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			download_helm_binaries "$BUNDLE_DIR" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "download_helm" "$exit_code" "$log_file"; then
			error "Failed to download Helm binaries"
		fi
	fi
	
	# Step 2: Download kubectl binaries
	if pre_execute_steps "download_kubectl" "Downloading kubectl binaries"; then
		if [[ "$VERBOSE" == "true" ]]; then
			download_kubectl_binaries "$BUNDLE_DIR"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			download_kubectl_binaries "$BUNDLE_DIR" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "download_kubectl" "$exit_code" "$log_file"; then
			error "Failed to download kubectl binaries"
		fi
	fi
	
	# Step 3: Download Azure CLI wheels
	if pre_execute_steps "download_azure_cli" "Downloading Azure CLI wheels"; then
		if [[ "$VERBOSE" == "true" ]]; then
			download_azure_cli_wheels "$BUNDLE_DIR"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			download_azure_cli_wheels "$BUNDLE_DIR" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "download_azure_cli" "$exit_code" "$log_file"; then
			error "Failed to download Azure CLI wheels"
		fi
	fi
	
	# Step 4: Download K3s installer
	if pre_execute_steps "download_k3s" "Downloading K3s installer"; then
		if [[ "$VERBOSE" == "true" ]]; then
			download_k3s_script "$BUNDLE_DIR"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			download_k3s_script "$BUNDLE_DIR" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "download_k3s" "$exit_code" "$log_file"; then
			error "Failed to download K3s installer"
		fi
	fi
	
	# Step 5: Generate installation scripts
	if pre_execute_steps "generate_scripts" "Generating installation scripts"; then
		if [[ "$VERBOSE" == "true" ]]; then
			generate_install_script "$BUNDLE_DIR"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			generate_install_script "$BUNDLE_DIR" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "generate_scripts" "$exit_code" "$log_file"; then
			error "Failed to generate installation scripts"
		fi
	fi
	
	# Step 6: Create manifest
	if pre_execute_steps "create_manifest" "Creating bundle manifest"; then
		if [[ "$VERBOSE" == "true" ]]; then
			create_manifest "$BUNDLE_DIR" "$BUNDLE_NAME"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			create_manifest "$BUNDLE_DIR" "$BUNDLE_NAME" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "create_manifest" "$exit_code" "$log_file"; then
			error "Failed to create bundle manifest"
		fi
	fi
	
	# Step 7: Create bundle tarball
	if pre_execute_steps "create_tarball" "Creating compressed bundle"; then
		if [[ "$VERBOSE" == "true" ]]; then
			create_bundle_tarball "$BUNDLE_DIR" "$BUNDLE_NAME"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			create_bundle_tarball "$BUNDLE_DIR" "$BUNDLE_NAME" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "create_tarball" "$exit_code" "$log_file"; then
			error "Failed to create bundle tarball"
		fi
	fi
	
	# Step 8: Update bundle manifest
	if pre_execute_steps "update_manifest" "Updating bundle manifest"; then
		if [[ "$VERBOSE" == "true" ]]; then
			update_bundle_manifest_file "$BUNDLE_NAME"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-bundle-$$.log"
			update_bundle_manifest_file "$BUNDLE_NAME" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "update_manifest" "$exit_code" "$log_file"; then
			error "Failed to update bundle manifest"
		fi
	fi
	
	# Get final bundle information
	bundle_file="bundles/${BUNDLE_NAME}.tar.gz"
	bundle_size=$(du -h "$bundle_file" | cut -f1)
	bundle_checksum=$(sha256sum "$bundle_file" | cut -d' ' -f1)
	
	# Show completion message
	echo ""
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}${CYAN}                     BUNDLE CREATED SUCCESSFULLY${NC}"
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	success "Offline installation bundle created successfully"
	echo -e "   ${BOLD}Bundle:${NC} bundles/${BUNDLE_NAME}.tar.gz"
	echo -e "   ${BOLD}Size:${NC} $bundle_size"
	echo -e "   ${BOLD}Checksum:${NC} sha256:$bundle_checksum"
	echo -e "   ${BOLD}Components:${NC} Helm v3.12.2, kubectl ${KUBECTL_VERSION}, Azure CLI wheels, K3s installer"
	echo ""
	echo -e "${BOLD}NEXT STEPS:${NC}"
	info "Transfer bundle to target system: scp bundles/${BUNDLE_NAME}.tar.gz user@target:/path/"
	info "Extract bundle: tar -xzf ${BUNDLE_NAME}.tar.gz"
	info "Install components: cd ${BUNDLE_NAME} && ./scripts/install-components.sh"
	info "Use offline mode: ./setup-k3s-arc.sh --offline [other-options]"
	echo ""
	echo -e "${BOLD}BANDWIDTH SAVINGS:${NC}"
	echo "   ${GEAR} This bundle eliminates ~300MB+ of downloads per installation"
	echo "   ${GEAR} Components are cached locally for repeated deployments"
	echo "   ${GEAR} Perfect for air-gapped or bandwidth-limited environments"
	echo ""
fi

# Cleanup handled by cleanup_on_exit trap