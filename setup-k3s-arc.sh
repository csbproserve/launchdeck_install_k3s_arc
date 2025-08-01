#!/bin/bash
# 2025.07.21 - CSB Dev <csbdev@cspire.com>
#
# Production RHEL 9 + K3s + Azure Arc Setup Script
# This script is idempotent and fully automated
#
# Usage: ./setup-k3s-arc.sh --client-id <id> --client-secret <secret> --tenant-id <tenant> --subscription-id <sub> --resource-group <rg> --cluster-name <n>

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

# skip() {
#     if [[ "$VERBOSE" == "true" ]]; then
#         echo -e "${BLUE}[$(date +'%H:%M:%S')] SKIP: $1${NC}"
#     fi
# }
# NOTE: Function commented out - only used once, could be replaced with verbose_log()

# Clear current line
clear_line() {
	if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
		printf "\r%*s\r" 80 ""
	fi
}

clear_progress() {
	clear_line
}

# Secure sudo password capture (single prompt for entire script)
capture_sudo_password() {
	if ! sudo -n true 2>/dev/null; then
		if [[ "$QUIET" != "true" ]]; then
			echo "${LOCK} Administrative privileges required for system configuration."
			echo "Enter sudo password (input hidden for security):"
		fi
		read -s -p "Password: " SUDO_PASSWORD
		echo ""
		
		# Validate password immediately
		if ! echo "$SUDO_PASSWORD" | sudo -S true 2>/dev/null; then
			error "Invalid password or insufficient privileges"
		fi
		
		if [[ "$QUIET" != "true" ]]; then
			echo ""
			info "Authentication successful - proceeding with deployment"
			echo ""
		fi
	fi
}

# Refresh sudo credentials using stored password (for post-time-sync)
refresh_sudo_credentials() {
	if [[ -n "$SUDO_PASSWORD" ]] && ! sudo -n true 2>/dev/null; then
		verbose_log "Refreshing sudo credentials after time synchronization"
		if ! echo "$SUDO_PASSWORD" | sudo -S true 2>/dev/null; then
			error "Failed to refresh administrative privileges"
		fi
		verbose_log "Sudo credentials refreshed successfully"
	fi
}

# Cleanup function for script exit
cleanup_on_exit() {
	# Clear sensitive password from memory
	if [[ -n "$SUDO_PASSWORD" ]]; then
		unset SUDO_PASSWORD
		verbose_log "Cleared sudo password from memory"
	fi
	
	# Clear remote management credentials from memory
	if [[ -n "$REMOTE_ACCESS_KEY" ]]; then
		unset REMOTE_ACCESS_KEY
		verbose_log "Cleared remote access credentials from memory"
	fi
	
	# Clear all sensitive variables from environment and process list
	unset AZURE_CLIENT_SECRET JOIN_TOKEN SERVER_IP NODE_ROLE SKIP_AZURE_COMPONENTS
	unset AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID AZURE_RESOURCE_GROUP
	unset AZURE_CLUSTER_NAME AZURE_LOCATION SYSTEM_ARCH HELM_ARCH KUBECTL_ARCH AZ_COMPATIBLE
	unset TEMP_DIR CURRENT_STEP TOTAL_STEPS STATE_FILE
	unset ENABLE_REMOTE_MGMT MGMT_ACCOUNT_NAME ACCESS_CREDENTIALS_READY SHOW_REMOTE_MGMT_STATUS
	
	verbose_log "Cleared sensitive variables from memory"
}

# Set up cleanup trap
trap cleanup_on_exit EXIT

# Unified system architecture detection
detect_system_architecture() {
	SYSTEM_ARCH=$(uname -m)
	case "$SYSTEM_ARCH" in
		x86_64) HELM_ARCH="amd64"; KUBECTL_ARCH="amd64"; AZ_COMPATIBLE=true ;;
		aarch64) HELM_ARCH="arm64"; KUBECTL_ARCH="arm64"; AZ_COMPATIBLE=false ;;
		armv7l) HELM_ARCH="arm"; KUBECTL_ARCH="arm"; AZ_COMPATIBLE=false ;;
		*) warn "Unknown architecture: $SYSTEM_ARCH. Using x86_64 defaults."
		   HELM_ARCH="amd64"; KUBECTL_ARCH="amd64"; AZ_COMPATIBLE=true ;;
	esac
	verbose_log "Architecture detected: $SYSTEM_ARCH -> helm:$HELM_ARCH, kubectl:$KUBECTL_ARCH"
}

# Check if offline installation completion marker exists
check_offline_completion_marker() {
	if [[ -f "$OFFLINE_COMPLETION_MARKER" ]]; then
		verbose_log "Offline installation completion marker found: $OFFLINE_COMPLETION_MARKER"
		return 0
	else
		verbose_log "Offline installation completion marker not found: $OFFLINE_COMPLETION_MARKER"
		return 1
	fi
}

# Validate offline Helm installation
validate_offline_helm() {
	if command -v helm >/dev/null 2>&1; then
		if helm version >/dev/null 2>&1; then
			local helm_version=$(helm version --short 2>/dev/null | cut -d' ' -f1 || echo "unknown")
			verbose_log "Offline Helm validated: $helm_version"
			return 0
		else
			verbose_log "Helm command found but not working (architecture mismatch?)"
			return 1
		fi
	else
		verbose_log "Helm command not found in PATH"
		return 1
	fi
}

# Validate offline kubectl installation
validate_offline_kubectl() {
	if command -v kubectl >/dev/null 2>&1; then
		if kubectl version --client >/dev/null 2>&1; then
			local kubectl_version=$(kubectl version --client 2>/dev/null | grep -o 'v[0-9][0-9.]*' | head -1 || echo "unknown")
			verbose_log "Offline kubectl validated: $kubectl_version"
			return 0
		else
			verbose_log "kubectl command found but not working (architecture mismatch?)"
			return 1
		fi
	else
		verbose_log "kubectl command not found in PATH"
		return 1
	fi
}

# Validate offline Azure CLI installation
validate_offline_azure_cli() {
	# Check both system-wide and user-local installations
	if command -v az >/dev/null 2>&1; then
		if az version >/dev/null 2>&1; then
			local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
			verbose_log "Offline Azure CLI validated: $az_version"
			return 0
		else
			verbose_log "Azure CLI command found but not working"
			return 1
		fi
	elif [[ -f "${HOME}/.local/bin/az" ]]; then
		if "${HOME}/.local/bin/az" version >/dev/null 2>&1; then
			local az_version=$("${HOME}/.local/bin/az" version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
			verbose_log "Offline Azure CLI validated (user-local): $az_version"
			return 0
		else
			verbose_log "Azure CLI found in user-local but not working"
			return 1
		fi
	else
		verbose_log "Azure CLI command not found in PATH or user-local"
		return 1
	fi
}

# Detect and validate offline components
detect_offline_components() {
	local components_available=true
	local missing_components=()
	
	verbose_log "Detecting offline components..."
	
	# Check completion marker first
	if ! check_offline_completion_marker; then
		verbose_log "Offline completion marker missing - components may not be properly installed"
		components_available=false
		missing_components+=("completion-marker")
	fi
	
	# Validate individual components
	if ! validate_offline_helm; then
		components_available=false
		missing_components+=("helm")
	fi
	
	if ! validate_offline_kubectl; then
		components_available=false
		missing_components+=("kubectl")
	fi
	
	if ! validate_offline_azure_cli; then
		components_available=false
		missing_components+=("azure-cli")
	fi
	
	if [[ "$components_available" == "true" ]]; then
		verbose_log "All offline components detected and validated"
		return 0
	else
		verbose_log "Missing offline components: ${missing_components[*]}"
		return 1
	fi
}

# Lightweight offline component detection for auto-detection (no verbose logging)
detect_offline_components_quiet() {
	# Check completion marker first
	if [[ ! -f "$OFFLINE_COMPLETION_MARKER" ]]; then
		return 1
	fi
	
	# Quick validation of core components
	if ! command -v helm >/dev/null 2>&1; then
		return 1
	fi
	
	if ! command -v kubectl >/dev/null 2>&1; then
		return 1
	fi
	
	if ! command -v az >/dev/null 2>&1 && [[ ! -f "${HOME}/.local/bin/az" ]]; then
		return 1
	fi
	
	# All core components available
	return 0
}

# Pre-execution step setup (handles progress display and completion checking)
pre_execute_steps() {
	local step_name="$1"
	local step_description="$2"
	
	CURRENT_STEP=$((CURRENT_STEP + 1))
	
	# Calculate step prefix length for consistent alignment
	local step_prefix="[$CURRENT_STEP/$TOTAL_STEPS] "
	local prefix_length=${#step_prefix}
	
	# Check if step is already completed
	if is_completed "$step_name"; then
		if [[ "$QUIET" != "true" ]]; then
			# Calculate dots for "Already configured" status alignment
			local status_text="Already configured"
			local total_content_length=$((prefix_length + ${#step_description} + 4 + ${#status_text}))  # 4 = "... " + space
			local dots_needed=$((80 - total_content_length))
			if [[ $dots_needed -lt 3 ]]; then dots_needed=3; fi
			local dots=$(printf "%*s" $dots_needed "" | tr ' ' '.')
			echo -e "${CYAN}[$CURRENT_STEP/$TOTAL_STEPS]${NC} $step_description$dots ${BLUE}${INFO} Already configured${NC}"
		fi
		return 1  # Signal to skip execution
	fi
	
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
		mark_completed "$step_name"
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

# Time synchronization check and fix function
# Critical: Must run BEFORE package operations to prevent GPG signature verification failures
check_and_fix_time_sync() {
	if [[ "$NO_NTP" == "true" ]]; then
		verbose_log "Skipping time sync (--no-ntp specified)"
		return 0
	fi
	
	log "${CLOCK} Checking system time synchronization..."
	
	# Check if system time is significantly off from Azure expected time
	local azure_time_check_url="https://management.azure.com"
	local time_tolerance_seconds=300  # 5 minutes tolerance
	
	# Try to get current Azure time from HTTP headers
	local azure_time=""
	if command -v curl >/dev/null 2>&1; then
		azure_time=$(curl -sI "$azure_time_check_url" 2>/dev/null | grep -i "^date:" | cut -d' ' -f2- | tr -d '\r')
	fi
	
	# Check local time sync services
	local time_sync_status="unknown"
	local time_sync_service=""
	
	# Check systemd-timesyncd first (most common)
	if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
		time_sync_service="systemd-timesyncd"
		if timedatectl status | grep -q "synchronized: yes"; then
			time_sync_status="synchronized"
		else
			time_sync_status="not_synchronized"
		fi
	# Check chronyd (RHEL/CentOS default)
	elif systemctl is-active --quiet chronyd 2>/dev/null; then
		time_sync_service="chronyd"
		if chronyc sources -v 2>/dev/null | grep -q "\^\*"; then
			time_sync_status="synchronized"
		else
			time_sync_status="not_synchronized"
		fi
	# Check ntpd (legacy)
	elif systemctl is-active --quiet ntpd 2>/dev/null; then
		time_sync_service="ntpd"
		if ntpq -p 2>/dev/null | grep -q "^\*"; then
			time_sync_status="synchronized"
		else
			time_sync_status="not_synchronized"
		fi
	else
		time_sync_service="none"
		time_sync_status="no_service"
	fi
	
	verbose_log "Time sync service: $time_sync_service, status: $time_sync_status"
	
	# Check if system time is significantly different from network time (force fix regardless of sync status)
	local time_needs_correction=false
	local network_time_epoch=""
	
	# Get network time for comparison
	if command -v curl >/dev/null 2>&1; then
		local network_time_header=$(curl -sI "https://www.google.com" 2>/dev/null | grep -i "^date:" | cut -d' ' -f2- | tr -d '\r' || echo "")
		if [[ -n "$network_time_header" ]]; then
			network_time_epoch=$(date -d "$network_time_header" +%s 2>/dev/null || echo "")
			local system_time_epoch=$(date +%s)
			
			if [[ -n "$network_time_epoch" ]]; then
				local time_diff=$((network_time_epoch - system_time_epoch))
				local time_diff_abs=${time_diff#-}  # absolute value
				
				verbose_log "System time epoch: $system_time_epoch, Network time epoch: $network_time_epoch"
				verbose_log "Time difference: $time_diff seconds ($((time_diff / 3600)) hours)"
				
				# If time difference is more than 5 minutes, force correction
				if [[ $time_diff_abs -gt 300 ]]; then
					time_needs_correction=true
					warn "Large time difference detected: $((time_diff / 3600)) hours, $((time_diff % 3600 / 60)) minutes"
				fi
			fi
		fi
	fi
	
	# If time is not synchronized OR needs correction due to large difference, try to fix it
	if [[ "$time_sync_status" != "synchronized" ]] || [[ "$time_needs_correction" == "true" ]]; then
		if [[ "$time_needs_correction" == "true" ]]; then
			warn "System time is significantly off from network time - forcing correction"
		else
			warn "System time synchronization issues detected"
		fi
		log "Attempting to fix time synchronization..."
		
		# Try to enable and start appropriate time sync service
		if command -v systemctl >/dev/null 2>&1; then
			if systemctl list-unit-files | grep -q "systemd-timesyncd"; then
				log "Enabling systemd-timesyncd..."
				if sudo systemctl enable systemd-timesyncd 2>/dev/null && sudo systemctl start systemd-timesyncd 2>/dev/null; then
					log "${CHECK} systemd-timesyncd started"
					time_sync_service="systemd-timesyncd"
				fi
			elif systemctl list-unit-files | grep -q "chronyd"; then
				log "Enabling chronyd..."
				if sudo systemctl enable chronyd 2>/dev/null && sudo systemctl start chronyd 2>/dev/null; then
					log "${CHECK} chronyd started"
					time_sync_service="chronyd"
				fi
			fi
			
			# Force aggressive time synchronization
			if [[ "$time_sync_service" == "chronyd" ]]; then
				log "${CLOCK} Forcing aggressive time synchronization with chronyd..."
				# Execute all chronyd operations in a single sudo session to avoid credential prompts
				sudo -n bash -c '
					chronyc burst 4/4 2>/dev/null || true
					sleep 5
					chronyc makestep 2>/dev/null || true
					sleep 3
					systemctl restart chronyd 2>/dev/null || true
					sleep 5
					chronyc makestep 2>/dev/null || true
					sleep 3
				'
			elif [[ "$time_sync_service" == "systemd-timesyncd" ]]; then
				log "${CLOCK} Forcing time synchronization with systemd-timesyncd..."
				sudo systemctl restart systemd-timesyncd 2>/dev/null || true
				sleep 10
			fi
			
			# Wait for sync to stabilize
			log "Waiting for time synchronization to stabilize..."
			sleep 15
		fi
		
		# Manual time sync as fallback using ntpdate if available
		if [[ "$time_needs_correction" == "true" ]] && command -v ntpdate >/dev/null 2>&1; then
			log "Attempting manual time sync with ntpdate..."
			if sudo ntpdate -s time.nist.gov 2>/dev/null || sudo ntpdate -s pool.ntp.org 2>/dev/null; then
				log "${CHECK} Manual time sync completed"
			fi
		fi
	fi
	
	# Final verification with detailed checking
	local current_time=$(date +%s)
	local current_date=$(date)
	verbose_log "Current system time: $current_date"
	
	# Get expected time from network (rough check)
	local network_time=""
	if command -v curl >/dev/null 2>&1; then
		network_time=$(curl -sI "https://www.google.com" 2>/dev/null | grep -i "^date:" | cut -d' ' -f2- | tr -d '\r' || echo "")
	fi
	
	if [[ -n "$network_time" ]]; then
		verbose_log "Network time reference: $network_time"
	fi
	
	# Check if timedatectl shows sync now
	if command -v timedatectl >/dev/null 2>&1; then
		local sync_status=$(timedatectl status 2>/dev/null | grep "synchronized:" | awk '{print $2}' || echo "unknown")
		if [[ "$sync_status" == "yes" ]]; then
			log "${CHECK} System time is synchronized with network time"
			log "Final system time: $current_date"
			return 0
		else
			warn "System time synchronization status: $sync_status"
		fi
	fi
	
	# Check if chronyd is actually synchronized
	if [[ "$time_sync_service" == "chronyd" ]]; then
		if chronyc sources 2>/dev/null | grep -q "^\^*"; then
			log "${CHECK} Chronyd shows synchronized time source"
			log "Final system time: $current_date"
			# Even if timedatectl says no, chronyd sync is usually reliable
			return 0
		else
			warn "Chronyd does not show synchronized time sources"
		fi
	fi
	
	# Final warning but don't fail - package operations may still work
	warn "${WARN}  Time sync verification incomplete - if package operations fail with GPG errors, time sync may be the cause"
	log "Current system time: $current_date"
	log "If Azure authentication fails with AADSTS700024 errors, manually sync time with: sudo chronyc makestep && sudo systemctl restart chronyd"
	return 0
}

# DNS troubleshooting function
dns_troubleshooting_guide() {
	echo -e "\n${BOLD}${YELLOW}DNS TROUBLESHOOTING GUIDE:${NC}"
	echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	echo -e "${BOLD}1. Manual DNS fix options:${NC}"
	echo "   $0 --dns-servers 8.8.8.8,8.8.4.4  # Use Google DNS (default)"
	echo "   $0 --dns-servers 1.1.1.1,1.0.0.1  # Use Cloudflare DNS"
	echo "   $0 --dns-servers 208.67.222.222,208.67.220.220  # Use OpenDNS"
	echo "   $0 --dns-servers YOUR_CORP_DNS1,YOUR_CORP_DNS2  # Use corporate DNS"
	echo ""
	echo -e "${BOLD}2. Reset DNS fix state (to reapply):${NC}"
	echo "   sed -i '/dns_fix_applied=completed/d' ~/.k3s-arc-setup-state"
	echo "   # Then re-run the script"
	echo ""
	echo -e "${BOLD}3. Restart services manually:${NC}"
	echo "   kubectl rollout restart deployment/coredns -n kube-system"
	echo "   kubectl rollout restart deployment -n azure-arc"
	echo ""
	echo -e "${BOLD}4. Check Arc agent logs:${NC}"
	echo "   kubectl logs -n azure-arc -l app.kubernetes.io/component=connect-agent"
	echo ""
	echo -e "${BOLD}ABOUT DNS SERVERS:${NC}"
	echo "   • Currently configured: $DNS_SERVERS"
	echo "   • 8.8.8.8, 8.8.4.4: Google Public DNS (default)"
	echo "   • 1.1.1.1, 1.0.0.1: Cloudflare DNS (privacy-focused)"
	echo "   • Corporate DNS: Recommended for enterprise environments"
	echo ""
}

# Enterprise error handling function
enterprise_error() {
	local error_msg="$1"
	local solution="$2"
	
	echo -e "\n${RED}${CROSS} DEPLOYMENT FAILED${NC}"
	echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "\n${BOLD}Issue:${NC} $error_msg"
	[[ -n "$solution" ]] && echo -e "${BOLD}Solution:${NC} $solution"
	
	echo -e "\n${BOLD}General Troubleshooting:${NC}\n   • Run: $0 --diagnostics\n   • Check logs: journalctl -u k3s -f\n   • Reset state: rm ~/.k3s-arc-setup-state\n"
	exit 1
}

# Header display for main execution
show_header() {
	if [[ "$QUIET" == "true" ]]; then
		return
	fi

	echo ""
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}${CYAN}                    K3S + AZURE ARC DEPLOYMENT${NC}"
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""

	if [[ -z "${NODE_ROLE}" ]]; then
		status "${ROCKET} Deploying single-node K3s cluster with Azure Arc integration"
		status "Configuration:"
		echo -e "   ${BOLD}Cluster:${NC} ${AZURE_CLUSTER_NAME}"
		echo -e "   ${BOLD}Location:${NC} ${AZURE_LOCATION}"
		echo -e "   ${BOLD}Resource Group:${NC} ${AZURE_RESOURCE_GROUP}"
	elif [[ "${NODE_ROLE}" == "server" && -z "${JOIN_TOKEN}" ]]; then
		status "${ROCKET} Initializing HA K3s cluster (first server node)"
		status "Configuration:"
		echo -e "   ${BOLD}Cluster:${NC} ${AZURE_CLUSTER_NAME}"
		echo -e "   ${BOLD}Location:${NC} ${AZURE_LOCATION}"
	elif [[ "${NODE_ROLE}" == "server" && -n "${JOIN_TOKEN}" ]]; then
		status "${GEAR} Adding server node to existing cluster"
		status "Configuration:"
		echo -e "   ${BOLD}Server IP:${NC} ${SERVER_IP}"
	else
		status "${GEAR} Adding worker node to existing cluster"
		status "Configuration:"
		echo -e "   ${BOLD}Server IP:${NC} ${SERVER_IP}"
	fi
	
	# Show offline mode status if enabled
	if [[ "$OFFLINE" == "true" ]]; then
		echo -e "   ${BOLD}Mode:${NC} ${FOLDER} Offline (using pre-installed components)"
	fi
	echo ""
}

# Usage function
usage() {
	echo -e "${BOLD}K3s + Azure Arc Setup Tool${NC}"
	echo ""
	echo -e "${BOLD}USAGE:${NC}"
	echo "    $0 [OPTIONS]"
	echo ""
	echo -e "${BOLD}DEPLOYMENT MODES:${NC}"
	echo -e "    ${GREEN}Single Node:${NC}        Complete K3s cluster with Azure Arc integration"
	echo -e "    ${GREEN}HA Cluster:${NC}         Multi-node cluster with high availability"
	echo -e "    ${GREEN}Join Existing:${NC}      Add nodes to existing clusters"
	echo ""
	echo -e "${BOLD}REQUIRED OPTIONS (for new clusters):${NC}"
	echo "    --client-id ID           Azure service principal client ID"
	echo "    --client-secret SECRET   Azure service principal client secret"
	echo "    --tenant-id ID           Azure tenant ID"
	echo "    --subscription-id ID     Azure subscription ID"
	echo "    --resource-group NAME    Azure resource group name"
	echo "    --cluster-name NAME      Arc cluster name"
	echo ""
	echo -e "${BOLD}CLUSTER OPTIONS:${NC}"
	echo "    --location REGION        Azure location (default: eastus)"
	echo "    --node-role TYPE         Node role: server|agent (default: single-node)"
	echo "    --server-ip IP           K3s server IP (for joining nodes)"
	echo "    --join-token TOKEN       K3s join token (for joining nodes)"
	echo ""
	echo -e "${BOLD}DNS OPTIONS:${NC}"
	echo "    --dns-servers LIST       Comma-separated DNS servers for CoreDNS (default: 8.8.8.8,8.8.4.4)"
	echo "    --no-fix-dns            Skip automatic DNS fixes (cluster DNS issues fixed by default)"
	echo ""
	echo -e "${BOLD}UTILITY OPTIONS:${NC}"
	echo "    --status                 Show current setup status"
	echo "    --diagnostics           Run detailed system diagnostics"
	echo "    --diagnose-service-principal  Test service principal configuration"
	echo "    --no-ntp                Skip time synchronization (reduces outbound network calls)"
	echo "    --offline               Use pre-installed offline components (auto-detected if available)"
	echo "    --verbose               Show detailed technical output"
	echo "    --quiet                 Minimal output (errors only)"
	echo "    --print-ssh-key         Output SSH private key at end (requires remote management)"
	echo "    --help                  Show this help message"
	echo ""
	echo -e "${BOLD}EXAMPLES:${NC}"
	echo "    # Deploy single-node cluster (automatic DNS fixes enabled by default)"
	echo "    $0 --client-id \$CLIENT_ID --client-secret \$CLIENT_SECRET \\"
	echo "       --tenant-id \$TENANT_ID --subscription-id \$SUB_ID \\"
	echo "       --resource-group my-rg --cluster-name my-cluster"
	echo ""
	echo "    # Deploy with custom DNS servers (for VM environments)"
	echo "    $0 --client-id \$CLIENT_ID --client-secret \$CLIENT_SECRET \\"
	echo "       --tenant-id \$TENANT_ID --subscription-id \$SUB_ID \\"
	echo "       --resource-group my-rg --cluster-name my-cluster \\"
	echo "       --dns-servers 1.1.1.1,1.0.0.1"
	echo ""
	echo "    # Deploy without automatic DNS fixes"
	echo "    $0 --client-id \$CLIENT_ID --client-secret \$CLIENT_SECRET \\"
	echo "       --tenant-id \$TENANT_ID --subscription-id \$SUB_ID \\"
	echo "       --resource-group my-rg --cluster-name my-cluster \\"
	echo "       --no-fix-dns"
	echo ""
	echo "    # Deploy using offline components (auto-detected or explicit)"
	echo "    $0 --client-id \$CLIENT_ID --client-secret \$CLIENT_SECRET \\"
	echo "       --tenant-id \$TENANT_ID --subscription-id \$SUB_ID \\"
	echo "       --resource-group my-rg --cluster-name my-cluster \\"
	echo "       --offline"
	echo ""
	echo "    # Check current status"
	echo "    $0 --status"
	echo ""
	echo "    # Join node to existing cluster"
	echo "    $0 --node-role agent --server-ip 10.0.1.10 --join-token \$TOKEN"
	echo ""
	echo -e "${BOLD}SUPPORT:${NC}"
	echo "    Run with --diagnostics for troubleshooting information"
	echo "    Documentation: https://docs.microsoft.com/azure-arc/kubernetes"
	echo ""
	exit 1
}

# Parse command line arguments
ACCESS_CREDENTIALS_READY=false    # Status flag
AZURE_CLIENT_ID=""
AZURE_CLIENT_SECRET=""
AZURE_CLUSTER_NAME=""
AZURE_LOCATION="eastus"
AZURE_RESOURCE_GROUP=""
AZURE_SUBSCRIPTION_ID=""
AZURE_TENANT_ID=""
DETAILED_DIAGNOSTICS=false
DIAGNOSE_SP_MODE=false
DNS_SERVERS="8.8.8.8,8.8.4.4"
ENABLE_REMOTE_MGMT=true           # Default to enabled
FIX_DNS=true
JOIN_TOKEN=""
MGMT_ACCOUNT_NAME="k3s"           # Default management account name
NO_NTP=false
NODE_ROLE=""
OFFLINE=false                     # Offline mode flag
OFFLINE_BASE_DIR="$HOME/.k3s-arc-offline"
OFFLINE_COMPLETION_MARKER="$OFFLINE_BASE_DIR/components-installed"
PRINT_SSH_KEY=false               # Print SSH key at end flag
REMOTE_ACCESS_KEY=""              # Base64-encoded private key storage
SERVER_IP=""
SHOW_REMOTE_MGMT_STATUS=false     # Status display flag
STATUS_ONLY=false

while [[ $# -gt 0 ]]; do
	case $1 in
		--client-id)
			AZURE_CLIENT_ID="$2"
			shift 2
			;;
		--client-secret)
			AZURE_CLIENT_SECRET="$2"
			shift 2
			;;
		--tenant-id)
			AZURE_TENANT_ID="$2"
			shift 2
			;;
		--subscription-id)
			AZURE_SUBSCRIPTION_ID="$2"
			shift 2
			;;
		--resource-group)
			AZURE_RESOURCE_GROUP="$2"
			shift 2
			;;
		--cluster-name)
			AZURE_CLUSTER_NAME="$2"
			shift 2
			;;
		--location)
			AZURE_LOCATION="$2"
			shift 2
			;;
		--node-role)
			NODE_ROLE="$2"
			shift 2
			;;
		--server-ip)
			SERVER_IP="$2"
			shift 2
			;;
		--join-token)
			JOIN_TOKEN="$2"
			shift 2
			;;
		--dns-servers)
			DNS_SERVERS="$2"
			shift 2
			;;
		--no-fix-dns)
			FIX_DNS=false
			shift
			;;
		--no-ntp)
			NO_NTP=true
			shift
			;;
		--status)
			STATUS_ONLY=true
			shift
			;;
		--diagnose-service-principal)
			DIAGNOSE_SP_MODE=true
			shift
			;;
		--diagnostics)
			DETAILED_DIAGNOSTICS=true
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
		--no-remote-management)
			ENABLE_REMOTE_MGMT=false
			shift
			;;
		--mgmt-account-name)
			MGMT_ACCOUNT_NAME="$2"
			shift 2
			;;
		--remote-management)
			SHOW_REMOTE_MGMT_STATUS=true
			shift
			;;
		--print-ssh-key)
			PRINT_SSH_KEY=true
			shift
			;;
		--offline)
			OFFLINE=true
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

# Validate --print-ssh-key compatibility
if [[ "$PRINT_SSH_KEY" == "true" ]] && [[ "$ENABLE_REMOTE_MGMT" == "false" ]]; then
	error "Cannot use --print-ssh-key with --no-remote-management. SSH keys are only generated when remote management is enabled."
fi

# Function to diagnose service principal setup
diagnose_service_principal() {
	echo ""
	log "=== SERVICE PRINCIPAL DIAGNOSTIC ==="
	echo ""

	log "Testing service principal authentication..."
	local needs_role_assignment=false

	# Test basic login
	if az login --service-principal \
		-u "${AZURE_CLIENT_ID}" \
		-p "${AZURE_CLIENT_SECRET}" \
		-t "${AZURE_TENANT_ID}" >/dev/null 2>&1; then
		log "${CHECK} Service principal authentication successful"

		# Get current account info
		local account_info=$(az account show 2>/dev/null || echo "")
		if [[ -n "$account_info" ]]; then
			local current_sub=$(echo "$account_info" | jq -r '.id // "none"' 2>/dev/null || echo "unknown")
			log "${CHECK} Current subscription context: $current_sub"

			if [[ "$current_sub" == "$AZURE_SUBSCRIPTION_ID" ]]; then
				log "${CHECK} Service principal has subscription-level access"
			else
				log "${INFO} Service principal appears to be resource-group-scoped"
			fi
		else
			log "${INFO} Service principal appears to be resource-group-scoped (no subscription access)"
		fi

		# Test resource group access
		log "Testing resource group access..."
		if az group show --name "${AZURE_RESOURCE_GROUP}" --subscription "${AZURE_SUBSCRIPTION_ID}" >/dev/null 2>&1; then
			log "${CHECK} Service principal can access resource group"

			# Test if we can list connected clusters (indicates Arc permissions)
			log "Testing Azure Arc permissions..."
			if az connectedk8s list --resource-group "${AZURE_RESOURCE_GROUP}" --subscription "${AZURE_SUBSCRIPTION_ID}" >/dev/null 2>&1; then
				log "${CHECK} Service principal can list connected clusters (Arc permissions confirmed)"
			else
				warn "${CROSS} Service principal cannot list connected clusters"
				log "This suggests missing 'Kubernetes Cluster - Azure Arc Onboarding' role"
				needs_role_assignment=true
			fi
		else
			error "${CROSS} Service principal cannot access resource group"
		fi

		# Check for existing cluster
		log "Checking for existing Arc cluster..."
		if az connectedk8s show --name "${AZURE_CLUSTER_NAME}" --resource-group "${AZURE_RESOURCE_GROUP}" --subscription "${AZURE_SUBSCRIPTION_ID}" >/dev/null 2>&1; then
			log "${INFO} Arc cluster '${AZURE_CLUSTER_NAME}' already exists"
		else
			log "${INFO} Arc cluster '${AZURE_CLUSTER_NAME}' does not exist (ready to create)"
		fi

		# Check system architecture for potential issues
		log "Checking system architecture compatibility..."
		case "$SYSTEM_ARCH" in
			x86_64)
				log "${CHECK} Architecture: $SYSTEM_ARCH (fully supported)"
				;;
			aarch64)
				log "${CHECK} Architecture: $SYSTEM_ARCH (ARM64 - supported)"
				;;
			armv7l)
				log "${WARN} Architecture: $SYSTEM_ARCH (ARM32 - limited support)"
				;;
			*)
				warn "${CROSS} Architecture: $SYSTEM_ARCH (unknown - may have compatibility issues)"
				;;
		esac

		# Check if helm is available and working
		if command -v helm >/dev/null 2>&1; then
			if helm version >/dev/null 2>&1; then
				log "${CHECK} Helm is installed and working"
			else
				warn "${CROSS} Helm is installed but not working (architecture mismatch?)"
			fi
		else
			log "${INFO} Helm not installed (will be installed during setup)"
		fi

		# Show role assignment instructions only if needed
		if [[ "$needs_role_assignment" == "true" ]]; then
			echo ""
			log "=== REQUIRED ROLE ASSIGNMENT ==="
			echo "Your service principal needs the 'Kubernetes Cluster - Azure Arc Onboarding' role."
			echo ""
			echo "To assign this role to your resource group (run as subscription admin):"
			echo ""
			echo "  az role assignment create \\"
			echo "    --assignee ${AZURE_CLIENT_ID} \\"
			echo "    --role 'Kubernetes Cluster - Azure Arc Onboarding' \\"
			echo "    --scope '/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}'"
			echo ""
			echo "To verify the assignment:"
			echo ""
			echo "  az role assignment list \\"
			echo "    --assignee ${AZURE_CLIENT_ID} \\"
			echo "    --scope '/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}'"
			echo ""
		else
			echo ""
			log "${CELEBRATION} DIAGNOSIS COMPLETE: Service principal is properly configured!"
			log "All required permissions are in place. Ready to proceed with Arc onboarding."
			echo ""
		fi

	else
		error "${CROSS} Service principal authentication failed - check client ID, secret, and tenant ID"
	fi
}

# Function for detailed system diagnostics
detailed_diagnostics() {
	echo ""
	log "=== DETAILED SYSTEM DIAGNOSTICS ==="
	echo ""

	# Validate required parameters first
	if [[ -z "${AZURE_CLIENT_ID}" || -z "${AZURE_CLUSTER_NAME}" || -z "${AZURE_RESOURCE_GROUP}" || -z "${AZURE_SUBSCRIPTION_ID}" ]]; then
		warn "Some Azure parameters missing - limited diagnostics available"
	fi

	# System architecture diagnostics
	log "${COMPUTER}  SYSTEM ARCHITECTURE:"
	local os_info=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
	echo "  OS: $os_info"
	echo "  Architecture: $SYSTEM_ARCH"
	echo "  Kernel: $(uname -r)"
	echo ""

	# K3s detailed status
	if systemctl is-active --quiet k3s 2>/dev/null; then
		log "${SHIP} K3S DETAILED STATUS:"
		echo "  Service Status: $(systemctl is-active k3s)"
		echo "  Uptime: $(systemctl show k3s --property=ActiveEnterTimestamp --value | cut -d' ' -f2-3)"

		if kubectl get nodes >/dev/null 2>&1; then
			echo "  Node Details:"
			kubectl get nodes -o wide | sed 's/^/    /'
			echo ""
			echo "  Resource Usage:"
			kubectl top nodes 2>/dev/null | sed 's/^/    /' || echo "    Metrics not available"
		fi
		echo ""
	fi

	# Arc agent detailed status
	if kubectl get namespace azure-arc >/dev/null 2>&1; then
		log "${LINK} ARC AGENTS DETAILED STATUS:"
		kubectl get pods -n azure-arc -o wide | sed 's/^/  /'
		echo ""

		# Check Arc connection from Azure perspective
		if [[ -n "$AZURE_CLUSTER_NAME" ]] && [[ -n "$AZURE_RESOURCE_GROUP" ]] && [[ -n "$AZURE_SUBSCRIPTION_ID" ]]; then
			log "${CLOUD}  AZURE ARC CLOUD STATUS:"
			local arc_info=$(az connectedk8s show --name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" 2>/dev/null)
			if [[ -n "$arc_info" ]]; then
				echo "$arc_info" | jq -r '
				"  Connectivity: " + .connectivityStatus,
				"  Provisioning: " + .provisioningState,
				"  Last Connect: " + .lastConnectivityTime,
				"  Agent Version: " + .agentVersion,
				"  Distribution: " + .distribution,
				"  Infrastructure: " + .infrastructure' 2>/dev/null || echo "  Status: Connected (jq not available for detailed parsing)"
			else
				echo "  ${CROSS} Unable to retrieve Arc status from Azure"
			fi
			echo ""
		fi
	fi

	# Flux detailed status
	if kubectl get namespace flux-system >/dev/null 2>&1; then
		log "${REFRESH} FLUX DETAILED STATUS:"
		kubectl get pods -n flux-system -o wide | sed 's/^/  /'
		echo ""

		# Check for any GitOps resources
		log "${BOOKS} GITOPS RESOURCES:"
		local git_repos=$(kubectl get gitrepository -A --no-headers 2>/dev/null | wc -l | tr -d '\n')
		local kustomizations=$(kubectl get kustomization -A --no-headers 2>/dev/null | wc -l | tr -d '\n')
		local helm_releases=$(kubectl get helmrelease -A --no-headers 2>/dev/null | wc -l | tr -d '\n')

		echo "  GitRepositories: $git_repos"
		echo "  Kustomizations: $kustomizations"
		echo "  HelmReleases: $helm_releases"

		if [[ $git_repos -gt 0 ]]; then
			echo ""
			echo "  GitRepository Details:"
			kubectl get gitrepository -A | sed 's/^/    /'
		fi

		if [[ $kustomizations -gt 0 ]]; then
			echo ""
			echo "  Kustomization Details:"
			kubectl get kustomization -A | sed 's/^/    /'
		fi
		echo ""
	fi

	# Network connectivity tests
	log "${GLOBE} NETWORK CONNECTIVITY:"
	echo "  External DNS Resolution:"
	echo "    google.com: $(nslookup google.com >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	echo "    github.com: $(nslookup github.com >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	echo "    management.azure.com: $(nslookup management.azure.com >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	
	echo "  Azure Service DNS:"
	echo "    login.microsoftonline.com: $(nslookup login.microsoftonline.com >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	echo "    management.azure.com: $(nslookup management.azure.com >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	echo "    letsencrypt.org: $(nslookup letsencrypt.org >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"

	echo "  Cluster Internal DNS:"
	if kubectl get nodes >/dev/null 2>&1; then
		echo "    kubernetes.default.svc.cluster.local: $(kubectl exec -n kube-system deployment/coredns -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
		echo "    kube-dns.kube-system.svc.cluster.local: $(kubectl exec -n kube-system deployment/coredns -- nslookup kube-dns.kube-system.svc.cluster.local >/dev/null 2>&1 && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
		
		# Check CoreDNS health
		local coredns_ready=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
		local coredns_desired=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
		echo "    CoreDNS Status: $([ "$coredns_ready" = "$coredns_desired" ] && [ "$coredns_ready" != "0" ] && echo "${CHECK} $coredns_ready/$coredns_desired ready" || echo "${CROSS} $coredns_ready/$coredns_desired ready")"
	else
		echo "    kubernetes cluster: ${CROSS} No cluster access"
	fi

	echo "  HTTP Connectivity:"
	echo "    GitHub API: $(curl -s --max-time 5 https://api.github.com >/dev/null && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	echo "    Azure API: $(curl -s --max-time 5 https://management.azure.com >/dev/null && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	echo "    Azure Login: $(curl -s --max-time 5 https://login.microsoftonline.com >/dev/null && echo "${CHECK} OK" || echo "${CROSS} FAILED")"
	echo ""

	# Resource usage
	log "${CHART} RESOURCE USAGE:"
	echo "  Memory:"
	free -h | sed 's/^/    /'
	echo ""
	echo "  Disk Space:"
	df -h / | sed 's/^/    /'
	echo ""
	echo "  Load Average: $(uptime | awk -F'load average:' '{print $2}' | xargs)"
	echo ""

	# Recent logs for troubleshooting
	log "${MEMO} RECENT SERVICE LOGS:"
	echo "  K3s Service (last 5 lines):"
	journalctl -u k3s --no-pager -n 5 2>/dev/null | sed 's/^/    /' || echo "    No logs available"
	echo ""

	if kubectl get namespace azure-arc >/dev/null 2>&1; then
		echo "  Arc Agent Errors (if any):"
		kubectl logs -n azure-arc -l app.kubernetes.io/component=connect-agent --tail=3 2>/dev/null | sed 's/^/    /' || echo "    No recent errors"
		echo ""
	fi

	if kubectl get namespace flux-system >/dev/null 2>&1; then
		echo "  Flux Controller Errors (if any):"
		kubectl logs -n flux-system -l app=source-controller --tail=3 2>/dev/null | sed 's/^/    /' || echo "    No recent errors"
		echo ""
	fi

	log "=== DIAGNOSTICS COMPLETE ==="
	echo ""
}

# Configure management access
configure_management_access() {
	if [[ "$ENABLE_REMOTE_MGMT" != "true" ]]; then
		return 0
	fi
	
	echo "     ${ARROW} Setting up management access..."
	
	if ! setup_secure_credentials; then
		error "Failed to configure management credentials"
		return 1
	fi
	
	if ! configure_system_access; then
		error "Failed to configure system access"
		return 1
	fi
	
	ACCESS_CREDENTIALS_READY=true
	return 0
}

# Setup secure credentials
setup_secure_credentials() {
	local temp_dir
	temp_dir=$(mktemp -d)
	
	# Generate SSH key pair
	if ! ssh-keygen -t rsa -b 4096 -f "$temp_dir/mgmt_key" -N "" -C "k3s-mgmt-$(date +%Y%m%d)" >/dev/null 2>&1; then
		rm -rf "$temp_dir"
		return 1
	fi
	
	# Store private key as base64 in memory
	REMOTE_ACCESS_KEY=$(base64 -w 0 < "$temp_dir/mgmt_key")
	
	# Configure SSH access
	if ! configure_ssh_access "$temp_dir/mgmt_key.pub"; then
		rm -rf "$temp_dir"
		return 1
	fi
	
	# Secure cleanup
	rm -rf "$temp_dir"
	return 0
}

# Configure SSH access
configure_ssh_access() {
	local public_key_file="$1"
	local mgmt_home="/home/$MGMT_ACCOUNT_NAME"
	
	# Create management account if it doesn't exist
	if ! id "$MGMT_ACCOUNT_NAME" >/dev/null 2>&1; then
		if ! sudo -n useradd -m -s /bin/bash "$MGMT_ACCOUNT_NAME" 2>/dev/null; then
			return 1
		fi
	fi
	
	# Setup SSH directory and authorized keys using consistent sudo pattern
	if ! sudo -n bash -c "
		mkdir -p '$mgmt_home/.ssh' &&
		cp '$public_key_file' '$mgmt_home/.ssh/authorized_keys' &&
		chmod 700 '$mgmt_home/.ssh' &&
		chmod 600 '$mgmt_home/.ssh/authorized_keys' &&
		chown -R '$MGMT_ACCOUNT_NAME:$MGMT_ACCOUNT_NAME' '$mgmt_home/.ssh'
	" 2>/dev/null; then
		return 1
	fi
	
	return 0
}

# Configure system access
configure_system_access() {
	local sudoers_file="/etc/sudoers.d/k3s-mgmt"
	local temp_sudoers
	temp_sudoers=$(mktemp)
	
	# Create sudoers configuration
	cat > "$temp_sudoers" << EOF
# K3s management access
$MGMT_ACCOUNT_NAME ALL=(ALL) NOPASSWD: ALL
EOF
	
	# Validate and install sudoers file using consistent sudo pattern
	if ! sudo -n bash -c "
		visudo -c -f '$temp_sudoers' >/dev/null 2>&1 &&
		cp '$temp_sudoers' '$sudoers_file' &&
		chmod 440 '$sudoers_file'
	" 2>/dev/null; then
		rm -f "$temp_sudoers"
		return 1
	fi
	
	rm -f "$temp_sudoers"
	return 0
}

# Enhanced status function
show_status() {
	local STATE_FILE="$HOME/.k3s-arc-setup-state"

	echo ""
	log "=== K3S + AZURE ARC SETUP STATUS ==="
	echo ""

	# Initialize state file if it doesn't exist
	if [[ ! -f "${STATE_FILE}" ]]; then
		touch "${STATE_FILE}"
	fi

	# Function to check if step is completed (for status mode)
	check_completed() {
		grep -q "^${1}=completed" "${STATE_FILE}" 2>/dev/null
	}

	# Local system status
	echo "${CLIPBOARD} LOCAL SYSTEM STATUS:"
	printf "  %-20s %s\n" "Time Sync:" "$(check_completed "time_sync_configured" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
	printf "  %-20s %s\n" "System Update:" "$(check_completed "system_update" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
	printf "  %-20s %s\n" "Required Packages:" "$(check_completed "packages_installed" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
	printf "  %-20s %s\n" "Firewall Config:" "$(check_completed "firewall_configured" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
	echo ""

	# K3s status
	echo "${SHIP} K3S STATUS:"
	printf "  %-20s %s\n" "K3s Installation:" "$(check_completed "k3s_installed" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
	printf "  %-20s %s\n" "K3s PATH Fix:" "$(check_completed "k3s_path_fixed" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
	printf "  %-20s %s\n" "kubectl Config:" "$(check_completed "kubectl_configured" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"

	# Check if K3s is actually running
	if systemctl is-active --quiet k3s 2>/dev/null; then
		printf "  %-20s %s\n" "K3s Service:" "${CHECK} RUNNING"
		if kubectl get nodes >/dev/null 2>&1; then
			NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d '\n')
			READY_COUNT=$(kubectl get nodes --no-headers | grep -c " Ready " | tr -d '\n')
			if [[ ${NODE_COUNT} -eq 1 ]]; then
				NODE_STATUS=$(kubectl get nodes --no-headers | awk '{print $2}' | head -1)
				printf "  %-20s %s\n" "Cluster Nodes:" "${CHECK} ${NODE_COUNT} node - ${NODE_STATUS}"
			else
				printf "  %-20s %s\n" "Cluster Nodes:" "${CHECK} ${READY_COUNT}/${NODE_COUNT} nodes ready"
			fi
		else
			printf "  %-20s %s\n" "Cluster Access:" "${CROSS} FAILED"
		fi
	else
		printf "  %-20s %s\n" "K3s Service:" "${CROSS} NOT RUNNING"
	fi

	# Show cluster configuration if in cluster mode
	if [[ -n "${NODE_ROLE}" ]]; then
		printf "  %-20s %s\n" "Node Role:" "${INFO} ${NODE_ROLE}"
	fi
	if [[ -n "${SERVER_IP}" ]]; then
		printf "  %-20s %s\n" "Server IP:" "${INFO} ${SERVER_IP}"
	fi

	# Show join token if this is a server node and token exists
	if [[ "${NODE_ROLE}" == "server" ]] && [[ -z "${JOIN_TOKEN}" ]]; then
		# Check if token file exists using stored credentials
		if [[ -n "$SUDO_PASSWORD" ]]; then
			if echo "$SUDO_PASSWORD" | sudo -S test -f /var/lib/rancher/k3s/server/node-token 2>/dev/null; then
				JOIN_TOKEN_FULL=$(echo "$SUDO_PASSWORD" | sudo -S cat /var/lib/rancher/k3s/server/node-token 2>/dev/null)
				printf "  %-20s %s\n" "Join Token:" "${INFO} ${JOIN_TOKEN_FULL}"
			fi
		else
			# Fallback for status mode without stored password
			if sudo -n test -f /var/lib/rancher/k3s/server/node-token 2>/dev/null; then
				JOIN_TOKEN_FULL=$(sudo -n cat /var/lib/rancher/k3s/server/node-token 2>/dev/null)
				printf "  %-20s %s\n" "Join Token:" "${INFO} ${JOIN_TOKEN_FULL}"
			else
				# Token file exists but requires sudo - show helpful message
				if [[ -e /var/lib/rancher/k3s/server ]]; then
					printf "  %-20s %s\n" "Join Token:" "${INFO} Available (run: sudo cat /var/lib/rancher/k3s/server/node-token)"
				fi
			fi
		fi
	fi
	echo ""

	# Azure CLI status
	echo "${CLOUD}  AZURE CLI STATUS:"
	if command -v az >/dev/null 2>&1 || [[ -f "${HOME}/.local/bin/az" ]]; then
		printf "  %-20s %s\n" "Azure CLI:" "${CHECK} INSTALLED"
		printf "  %-20s %s\n" "CLI Config:" "$(check_completed "azure_cli_configured" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
		printf "  %-20s %s\n" "Authentication:" "$(check_completed "azure_authenticated" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
		printf "  %-20s %s\n" "Providers:" "$(check_completed "providers_registered" && echo "${CHECK} REGISTERED" || echo "${CROSS} PENDING")"
	else
		printf "  %-20s %s\n" "Azure CLI:" "${CROSS} NOT INSTALLED"
	fi

	# Helm status
	if command -v helm >/dev/null 2>&1; then
		HELM_VERSION=$(helm version --short 2>/dev/null | cut -d' ' -f1 || echo "unknown")
		printf "  %-20s %s\n" "Helm:" "${CHECK} INSTALLED ($HELM_VERSION)"
		printf "  %-20s %s\n" "Helm Install:" "$(check_completed "helm_installed" && echo "${CHECK} COMPLETE" || echo "${CROSS} PENDING")"
	else
		printf "  %-20s %s\n" "Helm:" "${CROSS} NOT INSTALLED"
	fi

	# Architecture info with explanation
	printf "  %-20s %s\n" "Architecture:" "${INFO} ${SYSTEM_ARCH} (system CPU architecture)"
	echo ""

	# Arc connection status
	echo "${LINK} AZURE ARC STATUS:"
	printf "  %-20s %s\n" "Resource Group:" "$(check_completed "resource_group_created" && echo "${CHECK} READY" || echo "${CROSS} PENDING")"
	printf "  %-20s %s\n" "Arc Connection:" "$(check_completed "arc_connected" && echo "${CHECK} CONNECTED" || echo "${CROSS} PENDING")"
	printf "  %-20s %s\n" "Flux Extension:" "$(check_completed "flux_installed" && echo "${CHECK} INSTALLED" || echo "${CROSS} PENDING")"

	# Detailed Arc agent status if connected
	if check_completed "arc_connected" && kubectl get namespace azure-arc >/dev/null 2>&1; then
		echo ""
		echo "${WRENCH} ARC AGENT HEALTH:"
		local arc_pods_total=$(kubectl get pods -n azure-arc --no-headers 2>/dev/null | wc -l | tr -d '\n')
		local arc_pods_ready=$(kubectl get pods -n azure-arc --no-headers 2>/dev/null | grep -c "Running" | tr -d '\n' || echo "0")

		if [[ $arc_pods_ready -eq $arc_pods_total ]] && [[ $arc_pods_total -gt 0 ]]; then
			printf "  %-20s %s\n" "Arc Agents:" "${CHECK} ALL HEALTHY ($arc_pods_ready/$arc_pods_total running)"

			# Check actual connectivity to Azure if we have credentials
			if [[ -n "$AZURE_CLUSTER_NAME" ]] && [[ -n "$AZURE_RESOURCE_GROUP" ]] && [[ -n "$AZURE_SUBSCRIPTION_ID" ]]; then
				local connectivity_status=$(az connectedk8s show --name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" --query 'connectivityStatus' -o tsv 2>/dev/null || echo "unknown")
				local last_connect=$(az connectedk8s show --name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" --query 'lastConnectivityTime' -o tsv 2>/dev/null | cut -d'T' -f1 || echo "unknown")
				printf "  %-20s %s\n" "Azure Connectivity:" "${CHECK} $connectivity_status (last: $last_connect)"
			fi
		else
			printf "  %-20s %s\n" "Arc Agents:" "${WARN} ISSUES DETECTED ($arc_pods_ready/$arc_pods_total running)"
			echo "    Run 'kubectl get pods -n azure-arc' for details"
		fi
	fi

	# Detailed Flux status if installed
	if check_completed "flux_installed" && kubectl get namespace flux-system >/dev/null 2>&1; then
		echo ""
		echo "${REFRESH} FLUX HEALTH:"
		local flux_pods_total=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | wc -l | tr -d '\n')
		local flux_pods_ready=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | grep -c "Running" | tr -d '\n' || echo "0")

		if [[ $flux_pods_ready -eq $flux_pods_total ]] && [[ $flux_pods_total -gt 0 ]]; then
			printf "  %-20s %s\n" "Flux Controllers:" "${CHECK} ALL HEALTHY ($flux_pods_ready/$flux_pods_total running)"

			# Check for any GitRepositories or Kustomizations
			local git_repos=$(kubectl get gitrepository -n flux-system --no-headers 2>/dev/null | wc -l | tr -d '\n')
			local kustomizations=$(kubectl get kustomization -n flux-system --no-headers 2>/dev/null | wc -l | tr -d '\n')
			if [[ $git_repos -gt 0 ]] || [[ $kustomizations -gt 0 ]]; then
				printf "  %-20s %s\n" "GitOps Resources:" "${CHECK} $git_repos GitRepository(s), $kustomizations Kustomization(s)"
			else
				printf "  %-20s %s\n" "GitOps Resources:" "${INFO} No GitOps resources configured yet"
			fi
		else
			printf "  %-20s %s\n" "Flux Controllers:" "${WARN} ISSUES DETECTED ($flux_pods_ready/$flux_pods_total running)"
			echo "    Run 'kubectl get pods -n flux-system' for details"
		fi
	fi

	# Remote management status (only when requested)
	if [[ "$SHOW_REMOTE_MGMT_STATUS" == "true" ]]; then
		echo ""
		echo "${LOCK} REMOTE MANAGEMENT STATUS:"
		if id "$MGMT_ACCOUNT_NAME" >/dev/null 2>&1; then
			# Check if both SSH and sudo access are properly configured
			local ssh_configured=false
			local sudo_configured=false
			
			if sudo -n test -f "/home/$MGMT_ACCOUNT_NAME/.ssh/authorized_keys" 2>/dev/null; then
				ssh_configured=true
			fi
			
			if sudo -n test -f "/etc/sudoers.d/k3s-mgmt" 2>/dev/null; then
				sudo_configured=true
			fi
			
			# Determine overall status based on actual configuration
			if [[ "$ssh_configured" == "true" ]] && [[ "$sudo_configured" == "true" ]]; then
				printf "  %-20s %s\n" "Management Access:" "${CHECK} CONFIGURED"
				printf "  %-20s %s\n" "Account Name:" "${INFO} $MGMT_ACCOUNT_NAME"
				printf "  %-20s %s\n" "SSH Access:" "${CHECK} CONFIGURED"
				printf "  %-20s %s\n" "Sudo Access:" "${CHECK} CONFIGURED"
				
				# Show private key info if available (deployment mode only)
				if [[ "$ACCESS_CREDENTIALS_READY" == "true" ]] && [[ -n "$REMOTE_ACCESS_KEY" ]]; then
					printf "  %-20s %s\n" "Private Key:" "${CHECK} AVAILABLE (base64-encoded)"
					echo "    Access key stored in memory for secure transmission"
				fi
			else
				printf "  %-20s %s\n" "Management Access:" "${WARN} PARTIAL"
				printf "  %-20s %s\n" "Account Status:" "${CHECK} ACCOUNT EXISTS"
				printf "  %-20s %s\n" "SSH Access:" "$([[ "$ssh_configured" == "true" ]] && echo "${CHECK} CONFIGURED" || echo "${CROSS} NOT CONFIGURED")"
				printf "  %-20s %s\n" "Sudo Access:" "$([[ "$sudo_configured" == "true" ]] && echo "${CHECK} CONFIGURED" || echo "${CROSS} NOT CONFIGURED")"
			fi
		else
			printf "  %-20s %s\n" "Management Access:" "${CROSS} NOT CONFIGURED"
			printf "  %-20s %s\n" "Account Status:" "${CROSS} NO ACCOUNT"
		fi
	fi

	echo ""

	# Overall status calculation
	TOTAL_STEPS=11
	COMPLETED_STEPS=0

	for step in "time_sync_configured" "system_update" "packages_installed" "firewall_configured" "k3s_installed" "k3s_path_fixed" "kubectl_configured" "azure_cli_configured" "helm_installed" "arc_connected" "flux_installed"; do
		if check_completed "$step"; then
			((COMPLETED_STEPS++))
		fi
	done

	PERCENTAGE=$((COMPLETED_STEPS * 100 / TOTAL_STEPS))

	if [[ $COMPLETED_STEPS -eq $TOTAL_STEPS ]]; then
		echo "${CELEBRATION} OVERALL STATUS: COMPLETE ($COMPLETED_STEPS/$TOTAL_STEPS steps - $PERCENTAGE%)"
		echo "   Your cluster is ready for GitOps deployments!"
	elif [[ $COMPLETED_STEPS -gt 6 ]]; then
		echo "${WARN} OVERALL STATUS: NEARLY COMPLETE ($COMPLETED_STEPS/$TOTAL_STEPS steps - $PERCENTAGE%)"
		echo "   Setup is almost finished."
	elif [[ $COMPLETED_STEPS -gt 3 ]]; then
		echo "${REFRESH} OVERALL STATUS: IN PROGRESS ($COMPLETED_STEPS/$TOTAL_STEPS steps - $PERCENTAGE%)"
		echo "   Setup is in progress."
	else
		echo "${ROCKET} OVERALL STATUS: STARTING ($COMPLETED_STEPS/$TOTAL_STEPS steps - $PERCENTAGE%)"
		echo "   Run the setup command to begin installation."
	fi

	echo ""
	echo "${LIGHTBULB} LEGEND:"
	echo "   ${CHECK} = Working correctly"
	echo "   ${CROSS} = Failed or not installed"
	echo "   ${WARN} = Partial issues detected"
	echo "   ${INFO} = Informational (normal status)"
	echo ""
	echo "${FOLDER} State file: $STATE_FILE"
	echo "   To reset setup state: rm $STATE_FILE"
	echo ""

	# Clean up variables used in this function
	unset NODE_COUNT NODE_STATUS HELM_VERSION TOTAL_STEPS COMPLETED_STEPS PERCENTAGE
	unset arc_pods_total arc_pods_ready flux_pods_total flux_pods_ready git_repos kustomizations
	unset connectivity_status last_connect
}

# Handle special modes FIRST, before parameter validation
if [[ "$STATUS_ONLY" == "true" ]]; then
	# Detect system architecture for status display
	detect_system_architecture
	show_status
	exit 0
fi

if [[ "$DIAGNOSE_SP_MODE" == "true" ]]; then
	# Force verbose mode for diagnostics
	VERBOSE=true
	# Detect system architecture for diagnostics
	detect_system_architecture
	# Validate only the parameters needed for service principal diagnostics
	if [[ -z "$AZURE_CLIENT_ID" || -z "$AZURE_CLIENT_SECRET" || -z "$AZURE_TENANT_ID" || -z "$AZURE_SUBSCRIPTION_ID" || -z "$AZURE_RESOURCE_GROUP" ]]; then
		error "Missing required parameters for service principal diagnostics. Need: --client-id, --client-secret, --tenant-id, --subscription-id, --resource-group"
	fi

	# Set cluster name to a default if not provided (for diagnostic purposes)
	if [[ -z "${AZURE_CLUSTER_NAME}" ]]; then
		AZURE_CLUSTER_NAME="test-cluster"
		log "Using default cluster name for diagnostics: ${AZURE_CLUSTER_NAME}"
	fi

	diagnose_service_principal
	exit 0
fi

if [[ "$DETAILED_DIAGNOSTICS" == "true" ]]; then
	# Force verbose mode for diagnostics
	VERBOSE=true
	# Detect system architecture for diagnostics
	detect_system_architecture
	# For detailed diagnostics, we can work with partial parameters
	if [[ -z "$AZURE_CLUSTER_NAME" || -z "$AZURE_RESOURCE_GROUP" || -z "$AZURE_SUBSCRIPTION_ID" ]]; then
		warn "Some Azure parameters missing - detailed diagnostics will be limited"
	fi

	detailed_diagnostics
	exit 0
fi

# Validate required parameters for setup mode
if [[ -z "${AZURE_CLIENT_ID}" || -z "${AZURE_CLIENT_SECRET}" || -z "${AZURE_TENANT_ID}" || -z "${AZURE_SUBSCRIPTION_ID}" || -z "${AZURE_RESOURCE_GROUP}" || -z "${AZURE_CLUSTER_NAME}" ]]; then
	# For cluster modes, some parameters are optional
	if [[ -n "${NODE_ROLE}" ]]; then
		# Agent nodes don't need Azure credentials
		if [[ "${NODE_ROLE}" == "agent" ]]; then
			if [[ -z "${SERVER_IP}" || -z "${JOIN_TOKEN}" ]]; then
				error "Agent nodes require --server-ip and --join-token parameters"
			fi
		# Additional server nodes don't need Azure credentials
		elif [[ "${NODE_ROLE}" == "server" && -n "${JOIN_TOKEN}" ]]; then
			if [[ -z "${SERVER_IP}" ]]; then
				error "Additional server nodes require --server-ip parameter"
			fi
		# First server node needs full Azure credentials
		elif [[ "${NODE_ROLE}" == "server" && -z "${JOIN_TOKEN}" ]]; then
			if [[ -z "${AZURE_CLIENT_ID}" || -z "${AZURE_CLIENT_SECRET}" || -z "${AZURE_TENANT_ID}" || -z "${AZURE_SUBSCRIPTION_ID}" || -z "${AZURE_RESOURCE_GROUP}" || -z "${AZURE_CLUSTER_NAME}" ]]; then
				error "First server node requires all Azure parameters for Arc setup"
			fi
		fi
	else
		error "Missing required parameters for setup mode. Use --help for usage information."
	fi
fi

# Validate node role combinations
if [[ "${NODE_ROLE}" == "agent" && -z "${JOIN_TOKEN}" ]]; then
	error "Agent nodes must provide --join-token parameter"
fi

# Detect system architecture once at startup
detect_system_architecture

# Validate offline components if offline mode is enabled
if [[ "$OFFLINE" == "true" ]]; then
	verbose_log "Offline mode enabled - validating pre-installed components..."
	if ! detect_offline_components; then
		error "Offline mode specified but required components not found. Please install the offline bundle first:
		
   1. Download the offline bundle: ./build-k3s-arc-offline-install-bundle.sh
   2. Install components: ./install-k3s-arc-offline-install-bundle.sh
   3. Re-run this script with --offline flag
   
   Missing components can be checked individually:
   • Helm: command -v helm
   • kubectl: command -v kubectl
   • Azure CLI: command -v az
   • Completion marker: ls -la $OFFLINE_COMPLETION_MARKER"
	fi
	verbose_log "All offline components validated successfully"
fi

# Auto-detect offline components (only when offline mode not explicitly set)
OFFLINE_COMPONENTS_AVAILABLE=false
if [[ "$OFFLINE" != "true" ]] && detect_offline_components_quiet; then
	OFFLINE_COMPONENTS_AVAILABLE=true
fi

# Show header
show_header

# Show offline component availability message if detected
if [[ "$OFFLINE_COMPONENTS_AVAILABLE" == "true" ]] && [[ "$QUIET" != "true" ]]; then
	echo ""
	info "${LIGHTBULB} Offline components detected (Helm, kubectl, Azure CLI)"
	info "   Use --offline flag to skip downloads and use pre-installed components"
	info "   Continuing with online installation..."
	echo ""
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Run as a regular user with sudo privileges."
fi

# Get sudo authentication up front using secure single-prompt approach
capture_sudo_password

# State tracking
STATE_FILE="${HOME}/.k3s-arc-setup-state"

# Function to mark step as completed
mark_completed() {
	echo "$1=completed" >> "$STATE_FILE"
}

# Function to check if step is completed
is_completed() {
	grep -q "^$1=completed" "$STATE_FILE" 2>/dev/null
}


# Initialize state file if it doesn't exist
if [[ ! -f "$STATE_FILE" ]]; then
	touch "$STATE_FILE"
	verbose_log "Initialized state tracking file: $STATE_FILE"
fi

# Determine total steps for progress tracking
SKIP_AZURE_COMPONENTS=false
if [[ "${NODE_ROLE}" == "agent" ]] || [[ "${NODE_ROLE}" == "server" && -n "${JOIN_TOKEN}" ]]; then
	SKIP_AZURE_COMPONENTS=true
	if [[ "$OFFLINE" == "true" ]]; then
		TOTAL_STEPS=4  # time_sync_configured, firewall_configured, k3s_path_fixed, kubectl_configured (skip system_update, packages_installed, k3s_installed)
	else
		TOTAL_STEPS=7  # time_sync_configured, system_update, packages_installed, firewall_configured, k3s_installed, k3s_path_fixed, kubectl_configured
	fi
	if [[ "$VERBOSE" != "true" ]] && [[ "$QUIET" != "true" ]]; then
		log "Skipping Azure CLI, Helm, Arc, and Flux installation (cluster join mode)"
	fi
else
	if [[ "$OFFLINE" == "true" ]]; then
		TOTAL_STEPS=8  # time_sync_configured, firewall_configured, k3s_path_fixed, kubectl_configured, azure_cli_configured, azure_authenticated, resource_group_created, arc_connected, flux_installed (skip system_update, packages_installed, k3s_installed, azure_cli_installed, helm_installed)
		# Add remote management step if enabled
		if [[ "$ENABLE_REMOTE_MGMT" == "true" ]]; then
			TOTAL_STEPS=9
		fi
		if [[ "$VERBOSE" != "true" ]] && [[ "$QUIET" != "true" ]]; then
			log "Using offline components (skipping system updates, packages, K3s installation, Azure CLI installation, and Helm installation)"
		fi
	else
		TOTAL_STEPS=14  # Full deployment: time_sync_configured, system_update, packages_installed, firewall_configured, k3s_installed, k3s_path_fixed, kubectl_configured, azure_cli_installed, helm_installed, azure_cli_configured, azure_authenticated, resource_group_created, arc_connected, flux_installed
		# Add remote management step if enabled
		if [[ "$ENABLE_REMOTE_MGMT" == "true" ]]; then
			TOTAL_STEPS=15
		fi
	fi
fi

CURRENT_STEP=0

# Check and fix time synchronization FIRST (critical for package GPG verification)
if pre_execute_steps "time_sync_configured" "Checking system time synchronization" "true"; then
	if [[ "$VERBOSE" == "true" ]]; then
		check_and_fix_time_sync
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-setup-$$.log"
		check_and_fix_time_sync >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "time_sync_configured" "$exit_code" "$log_file"; then
		enterprise_error "Time synchronization check failed" "System time must be accurate for package GPG verification and Azure authentication"
	fi
	
	# Refresh credentials after time sync (system time jump invalidates sudo timestamps)
	refresh_sudo_credentials
fi

# Update system
if [[ "$OFFLINE" == "true" ]]; then
	verbose_log "Skipping system updates (offline mode)"
elif pre_execute_steps "system_update" "Updating system packages"; then
	if [[ "$VERBOSE" == "true" ]]; then
		sudo -n bash -c 'dnf update -y'
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-setup-$$.log"
		sudo -n bash -c 'dnf update -y' >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "system_update" "$exit_code" "$log_file"; then
		enterprise_error "System package update failed" "Check internet connectivity and package repositories"
	fi
fi

# Install required packages
if [[ "$OFFLINE" == "true" ]]; then
	verbose_log "Skipping package installation (offline mode)"
elif pre_execute_steps "packages_installed" "Installing dependencies"; then
	if [[ "$VERBOSE" == "true" ]]; then
		sudo -n bash -c 'dnf install -y curl wget git firewalld jq tar'
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-setup-$$.log"
		sudo -n bash -c 'dnf install -y curl wget git firewalld jq tar' >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "packages_installed" "$exit_code" "$log_file"; then
		enterprise_error "Required package installation failed" "Check internet connectivity and package repositories"
	fi
fi

# Configure firewall for K3s
if pre_execute_steps "firewall_configured" "Configuring firewall"; then
	if [[ "$VERBOSE" == "true" ]]; then
		sudo -n bash -c '
			systemctl enable firewalld &&
			systemctl start firewalld &&
			firewall-cmd --permanent --add-port=6443/tcp &&
			firewall-cmd --permanent --add-port=10250/tcp &&
			firewall-cmd --permanent --add-port=8472/udp &&
			firewall-cmd --permanent --add-port=51820/udp &&
			firewall-cmd --permanent --add-port=51821/udp &&
			firewall-cmd --reload'
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-setup-$$.log"
		sudo -n bash -c '
			systemctl enable firewalld &&
			systemctl start firewalld &&
			firewall-cmd --permanent --add-port=6443/tcp &&
			firewall-cmd --permanent --add-port=10250/tcp &&
			firewall-cmd --permanent --add-port=8472/udp &&
			firewall-cmd --permanent --add-port=51820/udp &&
			firewall-cmd --permanent --add-port=51821/udp &&
			firewall-cmd --reload' >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "firewall_configured" "$exit_code" "$log_file"; then
		enterprise_error "Firewall configuration failed" "Check firewalld service and port availability"
	fi
fi

# Install K3s based on node role
if [[ -z "${NODE_ROLE}" ]]; then
	# Single node mode
	if pre_execute_steps "k3s_installed" "Installing Kubernetes (K3s)" "true"; then
		if [[ "$VERBOSE" == "true" ]]; then
			curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --disable traefik --disable servicelb && sleep 30
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644 --disable traefik --disable servicelb >"$log_file" 2>&1 && sleep 30
			exit_code=$?
		fi
		
		if ! post_execute_steps "k3s_installed" "$exit_code" "$log_file"; then
			enterprise_error "K3s installation failed" "Check internet connectivity and system requirements"
		fi
	fi
elif [[ "${NODE_ROLE}" == "server" && -z "${JOIN_TOKEN}" ]]; then
	# First server in cluster
	if pre_execute_steps "k3s_installed" "Installing Kubernetes (K3s) - First Server" "true"; then
		if [[ "$VERBOSE" == "true" ]]; then
			curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 --disable traefik --disable servicelb --cluster-init && sleep 30
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 --disable traefik --disable servicelb --cluster-init >"$log_file" 2>&1 && sleep 30
			exit_code=$?
		fi
		
		if ! post_execute_steps "k3s_installed" "$exit_code" "$log_file"; then
			enterprise_error "K3s server installation failed" "Check internet connectivity and system requirements"
		fi
	fi
elif [[ "${NODE_ROLE}" == "server" && -n "${JOIN_TOKEN}" ]]; then
	# Additional server joining cluster
	if pre_execute_steps "k3s_installed" "Installing Kubernetes (K3s) - Additional Server" "true"; then
		if [[ "$VERBOSE" == "true" ]]; then
			K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${JOIN_TOKEN} curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 --disable traefik --disable servicelb && sleep 30
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${JOIN_TOKEN} curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 --disable traefik --disable servicelb >"$log_file" 2>&1 && sleep 30
			exit_code=$?
		fi
		
		if ! post_execute_steps "k3s_installed" "$exit_code" "$log_file"; then
			enterprise_error "K3s server join failed" "Check server IP, join token, and network connectivity"
		fi
	fi
elif [[ "${NODE_ROLE}" == "agent" ]]; then
	# Agent node joining cluster
	if pre_execute_steps "k3s_installed" "Installing Kubernetes (K3s) - Agent Node" "true"; then
		if [[ "$VERBOSE" == "true" ]]; then
			K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${JOIN_TOKEN} curl -sfL https://get.k3s.io | sh - && sleep 30
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${JOIN_TOKEN} curl -sfL https://get.k3s.io | sh - >"$log_file" 2>&1 && sleep 30
			exit_code=$?
		fi
		
		if ! post_execute_steps "k3s_installed" "$exit_code" "$log_file"; then
			enterprise_error "K3s agent join failed" "Check server IP, join token, and network connectivity"
		fi
	fi
fi

# Fix sudo PATH issue for k3s
if pre_execute_steps "k3s_path_fixed" "Configuring system paths"; then
	if [[ "$VERBOSE" == "true" ]]; then
		sudo -n bash -c 'ln -sf /usr/local/bin/k3s /usr/bin/k3s && ln -sf /usr/local/bin/kubectl /usr/bin/kubectl'
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-setup-$$.log"
		sudo -n bash -c 'ln -sf /usr/local/bin/k3s /usr/bin/k3s && ln -sf /usr/local/bin/kubectl /usr/bin/kubectl' >"$log_file" 2>&1
		exit_code=$?
	fi
	
	if ! post_execute_steps "k3s_path_fixed" "$exit_code" "$log_file"; then
		enterprise_error "System path configuration failed" "Check file system permissions"
	fi
fi

# Verify K3s installation
if systemctl is-active --quiet k3s; then
	verbose_log "K3s service is running"
	if sudo k3s kubectl get nodes >/dev/null 2>&1; then
		verbose_log "K3s installation verified successfully"
	else
		enterprise_error "K3s installed but kubectl access failed" "Check K3s installation and configuration"
	fi
else
	enterprise_error "K3s service is not running" "Check K3s installation and system resources"
fi

# Setup kubectl for current user
if pre_execute_steps "kubectl_configured" "Configuring cluster access"; then
	if [[ "$VERBOSE" == "true" ]]; then
		sudo -n bash -c "mkdir -p $HOME/.kube && cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config"
		exit_code=$?
	else
		log_file="/tmp/k3s-arc-setup-$$.log"
		sudo -n bash -c "mkdir -p $HOME/.kube && cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config && chown $(id -u):$(id -g) $HOME/.kube/config" >"$log_file" 2>&1
		exit_code=$?
	fi
	
	# Set KUBECONFIG globally if kubectl config was successful
	if [[ $exit_code -eq 0 ]]; then
		export KUBECONFIG=$HOME/.kube/config
		# Add to shell profile for permanent access
		if ! grep -q "export KUBECONFIG=$HOME/.kube/config" ~/.bashrc 2>/dev/null; then
			echo "export KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
			verbose_log "Added KUBECONFIG to ~/.bashrc for permanent access"
		fi
	fi
	
	if ! post_execute_steps "kubectl_configured" "$exit_code" "$log_file"; then
		enterprise_error "Cluster access configuration failed" "Check K3s installation and file permissions"
	fi
fi

# Install Azure CLI (skip for node joining and offline mode)
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	verbose_log "Skipping Azure CLI installation (node join mode)"
elif [[ "$OFFLINE" == "true" ]]; then
	verbose_log "Skipping Azure CLI installation (offline mode - should be pre-installed)"
	# Mark as completed since it should already be installed via offline bundle
	if ! is_completed "azure_cli_installed"; then
		mark_completed "azure_cli_installed"
	fi
elif pre_execute_steps "azure_cli_installed" "Installing Azure CLI$([ "$OFFLINE_COMPONENTS_AVAILABLE" == "true" ] && echo " (offline available)")"; then
		if [[ "$VERBOSE" == "true" ]]; then
			if command -v az >/dev/null 2>&1; then
				echo 'Azure CLI already installed'
				exit_code=0
			else
				sudo -n bash -c 'dnf install -y python3-pip' \
				&& pip3 install --user azure-cli \
				&& export PATH="${HOME}/.local/bin:${PATH}" \
				&& echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> ~/.bashrc
				exit_code=$?
			fi
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			if command -v az >/dev/null 2>&1; then
				echo 'Azure CLI already installed' >"$log_file" 2>&1
				exit_code=0
			else
				{
					sudo -n bash -c 'dnf install -y python3-pip' \
					&& pip3 install --user azure-cli \
					&& export PATH="${HOME}/.local/bin:${PATH}" \
					&& echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> ~/.bashrc
				} >"$log_file" 2>&1
				exit_code=$?
			fi
		fi
		
		if ! post_execute_steps "azure_cli_installed" "$exit_code" "$log_file"; then
			enterprise_error "Azure CLI installation failed" "Check internet connectivity and package repositories"
		fi
	fi
fi

# Install Helm (skip for node joining and offline mode)
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	# Skip step - don't increment counter manually
	verbose_log "Skipping Helm installation (node join mode)"
elif [[ "$OFFLINE" == "true" ]]; then
	verbose_log "Skipping Helm installation (offline mode - Helm should be pre-installed)"
	# Mark as completed since it should already be installed via offline bundle
	if ! is_completed "helm_installed"; then
		mark_completed "helm_installed"
	fi
else
	if pre_execute_steps "helm_installed" "Installing Helm$([ "$OFFLINE_COMPONENTS_AVAILABLE" == "true" ] && echo " (offline available)")"; then
		helm_url="https://get.helm.sh/helm-v3.12.2-linux-${HELM_ARCH}.tar.gz"
		
		if [[ "$VERBOSE" == "true" ]]; then
			TEMP_DIR=$(mktemp -d) \
			&& cd "$TEMP_DIR" \
			&& curl -fsSL "$helm_url" -o helm.tar.gz \
			&& tar -zxf helm.tar.gz \
			&& sudo mv "linux-${HELM_ARCH}/helm" /usr/local/bin/helm \
			&& sudo chmod +x /usr/local/bin/helm \
			&& sudo ln -sf /usr/local/bin/helm /usr/bin/helm \
			&& cd - \
			&& rm -rf "$TEMP_DIR"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			{
				TEMP_DIR=$(mktemp -d) \
				&& cd "$TEMP_DIR" \
				&& curl -fsSL "$helm_url" -o helm.tar.gz \
				&& tar -zxf helm.tar.gz \
				&& sudo mv "linux-${HELM_ARCH}/helm" /usr/local/bin/helm \
				&& sudo chmod +x /usr/local/bin/helm \
				&& sudo ln -sf /usr/local/bin/helm /usr/bin/helm \
				&& cd - \
				&& rm -rf "$TEMP_DIR"
			} >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "helm_installed" "$exit_code" "$log_file"; then
			enterprise_error "Helm installation failed" "Check internet connectivity and system architecture compatibility"
		fi
	fi
fi

# Configure Azure CLI (skip for node joining)
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	# Skip step - don't increment counter manually
	verbose_log "Skipping Azure CLI configuration (node join mode)"
else
	if pre_execute_steps "azure_cli_configured" "Configuring Azure CLI"; then
		if [[ "$VERBOSE" == "true" ]]; then
			az config set extension.use_dynamic_install=yes_without_prompt \
			&& az config set extension.dynamic_install_allow_preview=true
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			{
				az config set extension.use_dynamic_install=yes_without_prompt \
				&& az config set extension.dynamic_install_allow_preview=true
			} >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "azure_cli_configured" "$exit_code" "$log_file"; then
			enterprise_error "Azure CLI configuration failed" "Check Azure CLI installation"
		fi
	fi
fi

# Azure authentication (skip for node joining)
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	# Skip step - don't increment counter manually
	verbose_log "Skipping Azure authentication (node join mode)"
else
	if pre_execute_steps "azure_authenticated" "Authenticating with Azure"; then
		# Ensure Azure CLI is in PATH
		export PATH="${HOME}/.local/bin:${PATH}"
		
		# Add diagnostic logging for network/proxy issues before Azure authentication
		verbose_log "=== NETWORK CONNECTIVITY DIAGNOSTICS ==="
		
		# Check for proxy configuration
		if [[ -n "$HTTP_PROXY" ]] || [[ -n "$HTTPS_PROXY" ]] || [[ -n "$http_proxy" ]] || [[ -n "$https_proxy" ]]; then
			verbose_log "PROXY DETECTED:"
			verbose_log "  HTTP_PROXY: ${HTTP_PROXY:-${http_proxy:-'not set'}}"
			verbose_log "  HTTPS_PROXY: ${HTTPS_PROXY:-${https_proxy:-'not set'}}"
			warn "Corporate proxy detected - this may cause SSL certificate verification issues"
		else
			verbose_log "No proxy environment variables detected"
		fi
		
		# Test direct connectivity to Azure login endpoint
		verbose_log "Testing connectivity to Azure endpoints..."
		if command -v curl >/dev/null 2>&1; then
			# Test basic connectivity
			if curl -s --max-time 10 --connect-timeout 5 https://login.microsoftonline.com >/dev/null 2>&1; then
				verbose_log "✅ Basic connectivity to login.microsoftonline.com: SUCCESS"
			else
				warn "❌ Basic connectivity to login.microsoftonline.com: FAILED"
				warn "This indicates network connectivity or firewall issues"
			fi
			
			# Test SSL certificate validation specifically
			verbose_log "Testing SSL certificate validation..."
			ssl_test_result=$(curl -s --max-time 10 -I https://login.microsoftonline.com 2>&1)
			if echo "$ssl_test_result" | grep -q "HTTP/"; then
				verbose_log "✅ SSL certificate validation: SUCCESS"
			else
				warn "❌ SSL certificate validation: FAILED"
				if echo "$ssl_test_result" | grep -q "certificate"; then
					warn "Certificate-related error detected in connectivity test"
					verbose_log "SSL error details: $ssl_test_result"
				fi
			fi
			
			# Test Azure Resource Manager endpoint
			if curl -s --max-time 10 --connect-timeout 5 https://management.azure.com >/dev/null 2>&1; then
				verbose_log "✅ Connectivity to management.azure.com: SUCCESS"
			else
				warn "❌ Connectivity to management.azure.com: FAILED"
			fi
		fi
		
		# Check for network intermediaries that might intercept SSL
		verbose_log "Checking for network intermediaries..."
		if command -v traceroute >/dev/null 2>&1; then
			hop_count=$(traceroute -m 5 login.microsoftonline.com 2>/dev/null | grep -c "^ *[0-9]" || echo "unknown")
			verbose_log "Network hops to Azure: $hop_count (corporate networks often have many hops)"
		fi
		
		verbose_log "=== END NETWORK DIAGNOSTICS ==="
		
		if [[ "$VERBOSE" == "true" ]]; then
			az login --service-principal -u "${AZURE_CLIENT_ID}" -p "${AZURE_CLIENT_SECRET}" -t "${AZURE_TENANT_ID}"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			az login --service-principal -u "${AZURE_CLIENT_ID}" -p "${AZURE_CLIENT_SECRET}" -t "${AZURE_TENANT_ID}" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		# Enhanced error handling with specific guidance for network/proxy issues
		if ! post_execute_steps "azure_authenticated" "$exit_code" "$log_file"; then
			# Check if this is a certificate verification error
			if [[ -f "$log_file" ]] && grep -qi "certificate.*not.*valid\|CERTIFICATE_VERIFY_FAILED\|certificate.*future\|proxy.*intercept" "$log_file"; then
				verbose_log "Certificate verification error detected - analyzing failure pattern..."
				
				# Check if proxy is involved
				if [[ -n "$HTTP_PROXY" ]] || [[ -n "$HTTPS_PROXY" ]] || [[ -n "$http_proxy" ]] || [[ -n "$https_proxy" ]]; then
					enterprise_error "Azure authentication failed - Corporate proxy SSL interception detected" "Your corporate proxy is intercepting SSL traffic with self-signed certificates. Contact your IT team to add Azure CLI certificates to the trusted CA bundle, or configure proxy bypass for Azure endpoints."
				else
					enterprise_error "Azure authentication failed - SSL certificate verification issue" "This may be caused by network intermediaries or firewall SSL inspection. Try running the script again, or contact your network administrator about SSL inspection policies for Azure endpoints."
				fi
			else
				enterprise_error "Azure authentication failed" "Check service principal credentials and permissions"
			fi
		fi
	fi
fi

# Skip provider registration and mark as complete
if [[ "${SKIP_AZURE_COMPONENTS}" != "true" ]]; then
	if ! is_completed "providers_registered"; then
		mark_completed "providers_registered"
		verbose_log "Skipping provider registration (resource-group-scoped service principal)"
	fi
fi

# Resource group verification (skip for node joining)
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	# Skip step - don't increment counter manually
	verbose_log "Skipping resource group verification (node join mode)"
else
	if pre_execute_steps "resource_group_created" "Verifying resource group"; then
		if [[ "$VERBOSE" == "true" ]]; then
			az group show --name "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID"
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			az group show --name "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "resource_group_created" "$exit_code" "$log_file"; then
			enterprise_error "Resource group verification failed" "Check resource group exists and service principal has access"
		fi
	fi
fi

# Connect to Azure Arc (skip for node joining)
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	# Skip step - don't increment counter manually
	verbose_log "Skipping Azure Arc connection (node join mode)"
else
	# ARM64 architecture warning
	if [[ "$SYSTEM_ARCH" == "aarch64" ]]; then
		verbose_log "ARM64 architecture detected. Azure Arc agents may experience compatibility issues."
		verbose_log "ARM64 systems may have intermittent Arc agent stability problems."
	fi
	
	# Pre-install correct binaries for Azure CLI compatibility on non-x86_64 systems
	if [[ "$SYSTEM_ARCH" != "x86_64" ]]; then
		verbose_log "Pre-installing correct helm and kubectl for Azure CLI (${SYSTEM_ARCH} system detected)..."
		rm -rf ~/.azure/helm ~/.azure/kubectl-client 2>/dev/null || true
		mkdir -p ~/.azure/helm/v3.12.2/linux-amd64 ~/.azure/kubectl-client
		
		TEMP_DIR=$(mktemp -d)
		cd "$TEMP_DIR"
		
		# Install correct helm
		if curl -fsSL "https://get.helm.sh/helm-v3.12.2-linux-${HELM_ARCH}.tar.gz" -o helm.tar.gz >/dev/null 2>&1 && tar -zxf helm.tar.gz >/dev/null 2>&1; then
			cp "linux-${HELM_ARCH}/helm" ~/.azure/helm/v3.12.2/linux-amd64/helm
			chmod +x ~/.azure/helm/v3.12.2/linux-amd64/helm
			verbose_log "${CHECK} Successfully pre-installed ${HELM_ARCH} helm for Azure CLI"
		fi
		
		# Install correct kubectl
		KUBECTL_VERSION=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
		if curl -fsSL "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" -o kubectl >/dev/null 2>&1; then
			cp kubectl ~/.azure/kubectl-client/kubectl
			chmod +x ~/.azure/kubectl-client/kubectl
			verbose_log "${CHECK} Successfully pre-installed ${KUBECTL_ARCH} kubectl for Azure CLI"
		fi
		
		cd - >/dev/null
		rm -rf "$TEMP_DIR"
	fi
	
	# Check if cluster is already connected to Arc
	if az connectedk8s show --name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null 2>&1; then
		verbose_log "Cluster already connected to Azure Arc"
		if ! is_completed "arc_connected"; then
			mark_completed "arc_connected"
		fi
		if pre_execute_steps "arc_already_connected" "Azure Arc connection"; then
			if [[ "$VERBOSE" == "true" ]]; then
				echo 'Cluster already connected to Azure Arc'
				exit_code=$?
			else
				log_file="/tmp/k3s-arc-setup-$$.log"
				echo 'Cluster already connected to Azure Arc' >"$log_file" 2>&1
				exit_code=$?
			fi
			
			if ! post_execute_steps "arc_already_connected" "$exit_code" "$log_file"; then
				enterprise_error "Arc validation failed" "Unable to validate existing Arc connection"
			fi
		fi
	else
		if pre_execute_steps "arc_connected" "Connecting to Azure Arc" "true"; then
			# Ensure KUBECONFIG is set and valid for Azure CLI
			export KUBECONFIG=$HOME/.kube/config
			
			# Verify kubeconfig exists and is accessible
			if [[ ! -f "$KUBECONFIG" ]]; then
				echo ""
				echo "   ${BOLD}Error details:${NC}"
				echo "   Kubeconfig file not found: $KUBECONFIG"
				echo "   Run with --verbose to see full output"
				enterprise_error "Azure Arc connection failed" "Kubeconfig file missing - check kubectl configuration step"
			fi
			
			if [[ "$VERBOSE" == "true" ]]; then
				az connectedk8s connect --name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" --location "$AZURE_LOCATION"
				exit_code=$?
			else
				log_file="/tmp/k3s-arc-setup-$$.log"
				az connectedk8s connect --name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --subscription "$AZURE_SUBSCRIPTION_ID" --location "$AZURE_LOCATION" >"$log_file" 2>&1
				exit_code=$?
			fi
			
			if ! post_execute_steps "arc_connected" "$exit_code" "$log_file"; then
				# Provide specific guidance for common Arc connection failures
				if [[ -f "$log_file" ]] && grep -q "kubeconfig\|kube-config" "$log_file"; then
					enterprise_error "Azure Arc connection failed - Kubeconfig issue" "Kubeconfig file exists but may be invalid. Check kubectl configuration and cluster access. Run with --verbose for full error details."
				else
					enterprise_error "Azure Arc connection failed" "Check service principal permissions and network connectivity. Run with --verbose for full error details."
				fi
			fi
		fi
	fi
fi

# Install Flux extension (skip for node joining)
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	# Skip step - don't increment counter manually
	verbose_log "Skipping Flux installation (node join mode)"
else
	# Ensure k8s-extension is available
	if ! az extension list 2>/dev/null | grep -q "k8s-extension"; then
		verbose_log "Installing k8s-extension CLI extension..."
		az extension add --name k8s-extension --yes >/dev/null 2>&1
	fi
	
	# Enhanced DNS and Arc agent health check before installing Flux
	verbose_log "Checking DNS and Arc agent health before Flux installation..."
	
	# Comprehensive DNS health check with automatic fixes
	DNS_ISSUES=false
	ARC_CERTIFICATE_ISSUES=false
	verbose_log "Performing comprehensive DNS health checks..."
	
	# Test external DNS resolution
	if ! nslookup login.microsoftonline.com >/dev/null 2>&1; then
		warn "External DNS issue: Cannot resolve login.microsoftonline.com"
		DNS_ISSUES=true
	else
		verbose_log "${CHECK} External DNS working: login.microsoftonline.com"
	fi
	
	# Test Azure Resource Manager DNS (critical for Arc authentication)
	if ! nslookup management.azure.com >/dev/null 2>&1; then
		warn "Critical DNS issue: Cannot resolve management.azure.com (needed for Arc)"
		DNS_ISSUES=true
	else
		verbose_log "${CHECK} Azure Resource Manager DNS working: management.azure.com"
	fi
	
	# Test cluster internal DNS using a more reliable method
	verbose_log "Testing cluster internal DNS resolution..."
	
	# Clean up any leftover test pods first
	kubectl delete pod dns-test-$(date +%s) 2>/dev/null || true
	
	# Use a unique pod name to avoid conflicts
	DNS_TEST_POD="dns-test-$(date +%s)"
	
	# Test internal DNS resolution
	if kubectl run "$DNS_TEST_POD" --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
		verbose_log "${CHECK} Cluster internal DNS working"
	else
		# Try a simpler test as fallback
		if kubectl run "${DNS_TEST_POD}-simple" --image=busybox:1.35 --restart=Never --rm -i --timeout=20s -- nslookup kubernetes.default >/dev/null 2>&1; then
			verbose_log "${CHECK} Cluster internal DNS working (simple test)"
		else
			warn "Cluster DNS issue detected: Cannot resolve internal services"
			DNS_ISSUES=true
			
			# Get CoreDNS status for debugging
			verbose_log "CoreDNS pod status for diagnosis:"
			if [[ "$VERBOSE" == "true" ]]; then
				kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
				echo "Recent CoreDNS logs:"
				kubectl logs -n kube-system -l k8s-app=kube-dns --tail=5 2>/dev/null || echo "No logs available"
			fi
		fi
	fi
	
	# Check Arc agent status for certificate issues
	verbose_log "Checking Arc agent health..."
	ARC_PODS_NOT_READY=$(kubectl get pods -n azure-arc 2>/dev/null | grep -E "(ContainerCreating|CrashLoopBackOff|Error|Pending)" | wc -l | tr -d '\n')
	ARC_PODS_NOT_READY=${ARC_PODS_NOT_READY//[^0-9]/}  # Ensure numeric only
	CERTIFICATE_ISSUES=$(kubectl describe pods -n azure-arc 2>/dev/null | grep -c "certificate.*not found\|failed.*certificate\|MountVolume.*failed" | tr -d '\n' || echo "0")
	CERTIFICATE_ISSUES=${CERTIFICATE_ISSUES//[^0-9]/}  # Ensure numeric only
	
	if [[ $ARC_PODS_NOT_READY -gt 0 ]] || [[ $CERTIFICATE_ISSUES -gt 0 ]]; then
		echo "     ${GEAR} Arc agents need DNS fix ($ARC_PODS_NOT_READY pods not ready, $CERTIFICATE_ISSUES certificate issues)"
		ARC_CERTIFICATE_ISSUES=true
		
		if [[ $CERTIFICATE_ISSUES -gt 0 ]]; then
			verbose_log "Certificate-related issues detected in Arc agents - likely DNS-related"
			DNS_ISSUES=true  # Certificate issues are often caused by DNS problems
		fi
	else
		verbose_log "${CHECK} Arc agents appear healthy"
	fi
	
	# Check if DNS fix has already been applied to avoid repeated applications
	DNS_FIX_APPLIED=false
	if is_completed "dns_fix_applied"; then
		DNS_FIX_APPLIED=true
		verbose_log "DNS fix has already been applied previously"
	fi
	
	# Apply automatic DNS fix if issues detected, fix is enabled, and not already applied
	if [[ "$DNS_ISSUES" == "true" ]] && [[ "$FIX_DNS" == "true" ]] && [[ "$DNS_FIX_APPLIED" == "false" ]]; then
		echo "     ${GEAR} Applying DNS fix for Arc connectivity..."
		
		# Enhanced DNS fix that matches our successful manual fix
		verbose_log "${GEAR} Applying enhanced DNS fix for Arc agents..."
		
		# Backup current CoreDNS config
		kubectl get configmap coredns -n kube-system -o yaml > /tmp/coredns-backup.yaml 2>/dev/null || true
		
		# Parse DNS servers from the parameter (comma-separated)
		PRIMARY_DNS=$(echo "$DNS_SERVERS" | cut -d',' -f1 | xargs)
		SECONDARY_DNS=$(echo "$DNS_SERVERS" | cut -d',' -f2 | xargs)
		
		# Fallback to primary if secondary not provided
		if [[ -z "$SECONDARY_DNS" ]]; then
			SECONDARY_DNS="$PRIMARY_DNS"
		fi
		
		# Apply DNS fix with configured DNS servers
		echo "       ${GEAR} Updating CoreDNS with DNS servers ($PRIMARY_DNS, $SECONDARY_DNS)..."
		if kubectl patch configmap coredns -n kube-system --type merge -p="{
		  \"data\": {
			\"Corefile\": \".:53 {\\n    errors\\n    health {\\n       lameduck 5s\\n    }\\n    ready\\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\\n       pods insecure\\n       fallthrough in-addr.arpa ip6.arpa\\n       ttl 30\\n    }\\n    prometheus :9153\\n    forward . $PRIMARY_DNS $SECONDARY_DNS\\n    cache 30\\n    loop\\n    reload\\n    loadbalance\\n}\\n\"
		  }
		}" >/dev/null 2>&1; then
			echo "       ${CHECK} CoreDNS configmap updated with DNS servers: $PRIMARY_DNS, $SECONDARY_DNS"
			
			# Restart CoreDNS deployment
			echo "       ${REFRESH} Restarting CoreDNS deployment..."
			if kubectl rollout restart deployment/coredns -n kube-system >/dev/null 2>&1; then
				if kubectl rollout status deployment/coredns -n kube-system --timeout=90s >/dev/null 2>&1; then
					verbose_log "${CHECK} CoreDNS restart completed successfully"
					
					# Wait for DNS to stabilize
					verbose_log "${HOURGLASS} Waiting for DNS to stabilize..."
					sleep 30
					
					# Test DNS fix
					verbose_log "${TEST} Testing DNS fix..."
					if kubectl run dns-fix-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
						echo "     ${CHECK} Cluster DNS now working correctly"
						
						# Restart Arc agents to pick up DNS changes
						if [[ "$ARC_CERTIFICATE_ISSUES" == "true" ]]; then
							echo "     ${REFRESH} Restarting Arc agents to resolve certificate issues..."
							kubectl rollout restart deployment -n azure-arc >/dev/null 2>&1 || true
							kubectl delete pod -n azure-arc --all >/dev/null 2>&1 || true
							verbose_log "${HOURGLASS} Waiting 60 seconds for Arc agents to stabilize..."
							sleep 60
						fi
						
						echo "     ${CHECK} DNS fix completed successfully"
						
						# Mark DNS fix as applied
						mark_completed "dns_fix_applied"
					else
						warn "DNS test still failing after fix"
					fi
				else
					warn "CoreDNS restart timed out"
				fi
			else
				warn "Failed to restart CoreDNS deployment"
			fi
		else
			warn "Failed to update CoreDNS configmap"
		fi
		
	elif [[ "$DNS_ISSUES" == "true" ]] && [[ "$DNS_FIX_APPLIED" == "true" ]]; then
		warn "DNS issues detected, but DNS fix was already applied previously."
		warn "DNS problems may persist due to external factors (network, firewall, etc.)"
		verbose_log "Consider checking external DNS resolution and network connectivity"
	elif [[ "$DNS_ISSUES" == "true" ]] && [[ "$FIX_DNS" == "false" ]]; then
		warn "DNS issues detected but automatic fix disabled (--no-fix-dns)."
		warn "This may cause Arc agent certificate problems."
		dns_troubleshooting_guide
	fi
	
	# Arc agent health check
	ARC_PODS_READY=$(kubectl get pods -n azure-arc --no-headers 2>/dev/null | grep -c "Running" || echo "0")
	ARC_PODS_READY=${ARC_PODS_READY//[^0-9]/}  # Ensure numeric only
	ARC_PODS_TOTAL=$(kubectl get pods -n azure-arc --no-headers 2>/dev/null | wc -l | tr -d '\n')
	ARC_PODS_TOTAL=${ARC_PODS_TOTAL//[^0-9]/}  # Ensure numeric only
	
	# Check for certificate-related issues
	CERT_ISSUES=$(kubectl get pods -n azure-arc 2>/dev/null | grep -c "certificate\|ContainerCreating\|CrashLoopBackOff" || echo "0")
	CERT_ISSUES=${CERT_ISSUES//[^0-9]/}  # Ensure numeric only
	
	if [[ $ARC_PODS_READY -lt $ARC_PODS_TOTAL ]] || [[ $ARC_PODS_TOTAL -eq 0 ]] || [[ $CERT_ISSUES -gt 0 ]]; then
		warn "Arc agents not fully healthy ($ARC_PODS_READY/$ARC_PODS_TOTAL running, $CERT_ISSUES with issues)."
		
		if [[ "$DNS_ISSUES" == "true" ]]; then
			warn "DNS problems likely causing Arc agent certificate issues."
			warn "Fix DNS first: Restart CoreDNS with 'kubectl rollout restart deployment/coredns -n kube-system'"
		fi
		
		verbose_log "Waiting 60 seconds for Arc agents to stabilize..."
		sleep 60
	fi
	
	# Check if Flux extension already exists
	if az k8s-extension show --cluster-name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --cluster-type connectedClusters --name flux --subscription "$AZURE_SUBSCRIPTION_ID" >/dev/null 2>&1; then
		verbose_log "Flux extension already exists"
		if ! is_completed "flux_installed"; then
			mark_completed "flux_installed"
		fi
		if pre_execute_steps "flux_already_installed" "GitOps (Flux) extension"; then
			if [[ "$VERBOSE" == "true" ]]; then
				echo 'Flux extension already installed'
				exit_code=$?
			else
				log_file="/tmp/k3s-arc-setup-$$.log"
				echo 'Flux extension already installed' >"$log_file" 2>&1
				exit_code=$?
			fi
			
			if ! post_execute_steps "flux_already_installed" "$exit_code" "$log_file"; then
				enterprise_error "Flux validation failed" "Unable to validate existing Flux extension"
			fi
		fi
	else
		if pre_execute_steps "flux_installed" "Installing GitOps (Flux) extension" "true"; then
			if [[ "$VERBOSE" == "true" ]]; then
				timeout 600 az k8s-extension create --cluster-name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --cluster-type connectedClusters --extension-type microsoft.flux --name flux --subscription "$AZURE_SUBSCRIPTION_ID"
				exit_code=$?
			else
				log_file="/tmp/k3s-arc-setup-$$.log"
				timeout 600 az k8s-extension create --cluster-name "$AZURE_CLUSTER_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --cluster-type connectedClusters --extension-type microsoft.flux --name flux --subscription "$AZURE_SUBSCRIPTION_ID" >"$log_file" 2>&1
				exit_code=$?
			fi
			
			if ! post_execute_steps "flux_installed" "$exit_code" "$log_file"; then
				enterprise_error "Flux extension installation failed - likely DNS/certificate issue" "Arc agents appear unstable, often due to DNS problems preventing certificate generation. Check cluster DNS health and Arc agent logs for certificate errors."
			fi
		fi
	fi
fi

# Configure remote management access (if enabled)
if [[ "${SKIP_AZURE_COMPONENTS}" != "true" ]] && [[ "$ENABLE_REMOTE_MGMT" == "true" ]]; then
	if pre_execute_steps "remote_mgmt_configured" "Configuring remote management access"; then
		if [[ "$VERBOSE" == "true" ]]; then
			configure_management_access
			exit_code=$?
		else
			log_file="/tmp/k3s-arc-setup-$$.log"
			configure_management_access >"$log_file" 2>&1
			exit_code=$?
		fi
		
		if ! post_execute_steps "remote_mgmt_configured" "$exit_code" "$log_file"; then
			warn "Remote management setup failed - continuing without remote access"
			ACCESS_CREDENTIALS_READY=false
		fi
	fi
fi

# Verify final setup
verbose_log "Verifying final setup..."
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	verbose_log "Cluster node setup verification..."
	if kubectl get nodes >/dev/null 2>&1; then
		verbose_log "Cluster access verified"
		NODE_COUNT=$(kubectl get nodes --no-headers | wc -l | tr -d '\n')
		verbose_log "Cluster now has ${NODE_COUNT} node(s)"
	else
		enterprise_error "Cluster access verification failed" "Check K3s installation and kubectl configuration"
	fi
else
	# Full verification for single node or first server
	if az connectedk8s show --name "${AZURE_CLUSTER_NAME}" --resource-group "${AZURE_RESOURCE_GROUP}" --subscription "${AZURE_SUBSCRIPTION_ID}" >/dev/null 2>&1; then
		verbose_log "Arc connection verified"
	else
		enterprise_error "Arc connection verification failed" "Check Azure Arc setup and connectivity"
	fi

	if kubectl get namespaces | grep -q flux-system; then
		verbose_log "Flux system namespace found"
	else
		warn "Flux system namespace not found - extension may still be installing"
	fi
fi

# Show final status
echo ""
if [[ "${SKIP_AZURE_COMPONENTS}" == "true" ]]; then
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}${CYAN}                        NODE SUCCESSFULLY JOINED${NC}"
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	success "Node has been successfully added to the K3s cluster"
	echo -e "   ${BOLD}Role:${NC} ${NODE_ROLE}"
	echo -e "   ${BOLD}Server:${NC} ${SERVER_IP}"
	echo ""
else
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo -e "${BOLD}${CYAN}                      DEPLOYMENT SUCCESSFUL${NC}"
	echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
	echo ""
	success "Your K3s cluster is connected to Azure Arc and ready for GitOps deployments"
	echo -e "   ${BOLD}Cluster:${NC} ${AZURE_CLUSTER_NAME}"
	echo -e "   ${BOLD}Resource Group:${NC} ${AZURE_RESOURCE_GROUP}"
	echo -e "   ${BOLD}Azure Portal:${NC} Azure Arc > Kubernetes clusters"
	echo ""

	# Show remote management credentials if configured (verbose mode OR print-ssh-key flag)
	if [[ "$ACCESS_CREDENTIALS_READY" == "true" ]] && [[ -n "$REMOTE_ACCESS_KEY" ]] && ([[ "$VERBOSE" == "true" ]] || [[ "$PRINT_SSH_KEY" == "true" ]]); then
		echo -e "${BOLD}REMOTE MANAGEMENT ACCESS:${NC}"
		echo -e "   ${BOLD}Account:${NC} $MGMT_ACCOUNT_NAME"
		echo -e "   ${BOLD}SSH Access:${NC} Complete privileges configured"
		echo -e "   ${BOLD}Private Key (base64):${NC}"
		echo "   $REMOTE_ACCESS_KEY"
		echo ""
		echo -e "${BOLD}Connection Command:${NC}"
		echo "   # Save the key and connect:"
		echo "   echo '$REMOTE_ACCESS_KEY' | base64 -d > ~/.ssh/${AZURE_CLUSTER_NAME}_k3s_mgmt_key"
		echo "   chmod 600 ~/.ssh/${AZURE_CLUSTER_NAME}_k3s_mgmt_key"
		echo "   ssh -i ~/.ssh/${AZURE_CLUSTER_NAME}_k3s_mgmt_key $MGMT_ACCOUNT_NAME@$(hostname -I | awk '{print $1}')"
		echo ""
	fi

	# Show join token for first server
	if [[ "${NODE_ROLE}" == "server" && -z "${JOIN_TOKEN}" ]]; then
		# Check if token file exists and get token using stored credentials
		if [[ -n "$SUDO_PASSWORD" ]] && echo "$SUDO_PASSWORD" | sudo -S test -f /var/lib/rancher/k3s/server/node-token 2>/dev/null; then
			JOIN_TOKEN_FOR_DISPLAY=$(echo "$SUDO_PASSWORD" | sudo -S cat /var/lib/rancher/k3s/server/node-token 2>/dev/null)
			if [[ -n "$JOIN_TOKEN_FOR_DISPLAY" ]]; then
				echo -e "${BOLD}CLUSTER EXPANSION:${NC}"
				echo "   To add server nodes:"
				echo "   $0 --node-role server --server-ip $(hostname -I | awk '{print $1}') --join-token $JOIN_TOKEN_FOR_DISPLAY"
				echo ""
				echo "   To add worker nodes:"
				echo "   $0 --node-role agent --server-ip $(hostname -I | awk '{print $1}') --join-token $JOIN_TOKEN_FOR_DISPLAY"
				echo ""
			fi
		fi
	fi
fi

# echo -e "${BOLD}NEXT STEPS:${NC}"
# info "Check status: $0 --status"
# info "Run diagnostics: $0 --diagnostics"
# info "View cluster: kubectl get nodes"
# echo ""

# Final cleanup handled by cleanup_on_exit trap