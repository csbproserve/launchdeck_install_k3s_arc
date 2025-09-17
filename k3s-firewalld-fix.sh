#!/bin/bash
# k3s-firewalld-fix.sh
#
# Configures firewalld to work properly with K3s cluster networking
# Fixes pod-to-pod communication issues caused by firewalld blocking K3s traffic
#
# This script adds K3s network interfaces and pod networks to firewalld trusted zone
# to allow proper pod-to-pod communication while maintaining firewall security.
#
# Usage: sudo ./k3s-firewalld-fix.sh
# 
# Compatible with: Rocky Linux, RHEL, CentOS, Fedora with firewalld
# K3s versions: All versions with default Flannel CNI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Function to log with timestamp
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if firewalld is running
check_firewalld() {
    if systemctl is-active --quiet firewalld; then
        return 0  # firewalld is running
    else
        return 1  # firewalld is not running
    fi
}

# Function to check if K3s is installed
check_k3s() {
    if command -v k3s >/dev/null 2>&1 || [[ -f /usr/local/bin/k3s ]]; then
        return 0  # K3s is installed
    else
        return 1  # K3s not found
    fi
}

# Function to wait for K3s interfaces to be created
wait_for_k3s_interfaces() {
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ip link show cni0 >/dev/null 2>&1; then
            log "${GREEN}✅ K3s cni0 interface detected${NC}"
            return 0
        fi
        
        log "${YELLOW}⏳ Waiting for K3s interfaces to be created... (attempt $attempt/$max_attempts)${NC}"
        sleep 2
        ((attempt++))
    done
    
    log "${YELLOW}⚠️  K3s cni0 interface not yet available. Continuing anyway...${NC}"
    return 1
}

log "${BLUE}🚀 K3s firewalld configuration script starting...${NC}"

# Check if firewalld is running
if ! check_firewalld; then
    log "${GREEN}✅ firewalld is not running - no configuration needed${NC}"
    log "${BLUE}💡 K3s networking should work without firewalld interference${NC}"
    exit 0
fi

# Check if K3s is installed
if ! check_k3s; then
    log "${RED}❌ K3s not found. Please install K3s first.${NC}"
    exit 1
fi

log "${YELLOW}🔍 firewalld is running - configuring for K3s compatibility...${NC}"

# Show current firewalld configuration
log "${BLUE}📋 Current firewalld trusted zone configuration:${NC}"
firewall-cmd --zone=trusted --list-all || true

# Wait for K3s interfaces (optional - script works even if they don't exist yet)
wait_for_k3s_interfaces

# Configure firewalld for K3s networking
log "${YELLOW}🔧 Adding K3s networks to firewalld trusted zone...${NC}"

# Add cni0 bridge interface to trusted zone
log "   Adding cni0 interface to trusted zone..."
if firewall-cmd --permanent --zone=trusted --add-interface=cni0; then
    log "${GREEN}   ✅ cni0 added successfully${NC}"
else
    log "${YELLOW}   ⚠️  cni0 may not exist yet or already configured${NC}"
fi

# Add flannel.1 VXLAN interface to trusted zone  
log "   Adding flannel.1 interface to trusted zone..."
if firewall-cmd --permanent --zone=trusted --add-interface=flannel.1; then
    log "${GREEN}   ✅ flannel.1 added successfully${NC}"
else
    log "${YELLOW}   ⚠️  flannel.1 may not exist yet or already configured${NC}"
fi

# Add K3s pod network to trusted zone
log "   Adding K3s pod network (10.42.0.0/16) to trusted zone..."
if firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16; then
    log "${GREEN}   ✅ Pod network 10.42.0.0/16 added successfully${NC}"
else
    log "${YELLOW}   ⚠️  Pod network may already be configured${NC}"
fi

# Add K3s service network to trusted zone (optional, for service networking)
log "   Adding K3s service network (10.43.0.0/16) to trusted zone..."
if firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16; then
    log "${GREEN}   ✅ Service network 10.43.0.0/16 added successfully${NC}"
else
    log "${YELLOW}   ⚠️  Service network may already be configured${NC}"
fi

# Reload firewalld configuration
log "${YELLOW}🔄 Reloading firewalld configuration...${NC}"
if firewall-cmd --reload; then
    log "${GREEN}✅ firewalld configuration reloaded${NC}"
else
    log "${RED}❌ Failed to reload firewalld configuration${NC}"
    exit 1
fi

# Show updated configuration
log "${BLUE}📋 Updated firewalld trusted zone configuration:${NC}"
firewall-cmd --zone=trusted --list-all

# Check if K3s is running and provide guidance
if systemctl is-active --quiet k3s; then
    log "${GREEN}✅ K3s is running${NC}"
    log "${YELLOW}💡 Recommended: Restart Crossplane pods to clear connection cache:${NC}"
    log "   kubectl delete pods -n crossplane-system -l app=crossplane"
else
    log "${YELLOW}💡 K3s service is not running. Start it when ready:${NC}"
    log "   sudo systemctl start k3s"
fi

log "${GREEN}🎉 K3s firewalld configuration completed successfully!${NC}"

# Show verification steps
log "${YELLOW}📋 Verification steps:${NC}"
log "1. Start/restart K3s: sudo systemctl restart k3s"
log "2. Wait for pods to be ready: kubectl get pods -A"
log "3. Test pod-to-pod connectivity"
log "4. Check Crossplane function communication"
log ""
log "${BLUE}🔒 Security note: firewalld remains active and secure${NC}"
log "   Only K3s internal networks (10.42.0.0/16, 10.43.0.0/16) are trusted"
log "   External traffic is still filtered by firewalld rules"