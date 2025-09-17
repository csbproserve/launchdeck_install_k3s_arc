#!/bin/bash
# k3s-netpol-cleanup.sh
# 
# Fixes persistent K3s NetworkPolicy iptables rules (KUBE-NWPLCY chains)
# that remain active even after NetworkPolicy resources are removed from cluster.
#
# This is a known K3s limitation where kube-router netpol controller iptables
# rules persist and continue blocking pod-to-pod communication.
#
# Reference: https://docs.k3s.io/networking/networking-services
#
# Usage: sudo ./k3s-netpol-cleanup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to check if KUBE-NWPLCY chains exist
check_netpol_chains() {
    if iptables -t filter -L | grep -q 'KUBE-NWPLCY'; then
        return 0  # Chains exist
    else
        return 1  # No chains found
    fi
}

log "${YELLOW}K3s NetworkPolicy iptables cleanup starting...${NC}"

# Check if cleanup is needed
if ! check_netpol_chains; then
    log "${GREEN}✅ No KUBE-NWPLCY chains found - cleanup not needed${NC}"
    exit 0
fi

log "🔍 Found KUBE-NWPLCY chains that need cleanup"

# Create backup
BACKUP_FILE="/tmp/iptables-backup-$(date +%Y%m%d-%H%M%S).txt"
log "💾 Creating iptables backup at: $BACKUP_FILE"
iptables-save > "$BACKUP_FILE"

# Show current KUBE-NWPLCY chains for reference
log "📋 Current KUBE-NWPLCY chains:"
iptables -t filter -L | grep -E 'KUBE-NWPLCY|Chain KUBE-NWPLCY' | head -10

# Apply K3s NetworkPolicy cleanup method
log "🧹 Applying K3s NetworkPolicy cleanup..."
iptables-save | grep -v 'KUBE-NWPLCY' | iptables-restore

# Verify cleanup
log "🔍 Verifying cleanup results..."
if check_netpol_chains; then
    log "${YELLOW}⚠️  Some KUBE-NWPLCY rules may still exist:${NC}"
    iptables -t filter -L | grep -E 'KUBE-NWPLCY|Chain KUBE-NWPLCY'
    log "${YELLOW}You may need to restart K3s service if rules persist:${NC}"
    log "    sudo systemctl restart k3s"
    exit 1
else
    log "${GREEN}✅ All KUBE-NWPLCY chains successfully removed${NC}"
fi

# Check if K3s is running and suggest restart if needed
if systemctl is-active --quiet k3s; then
    log "${YELLOW}💡 K3s is running. Consider restarting Crossplane pods to clear connection cache:${NC}"
    log "    kubectl delete pods -n crossplane-system -l app=crossplane"
else
    log "${YELLOW}💡 K3s service is not running. Start it when ready:${NC}"
    log "    sudo systemctl start k3s"
fi

log "${GREEN}🎉 K3s NetworkPolicy cleanup completed successfully!${NC}"
log "📄 Backup saved at: $BACKUP_FILE"

# Show next steps
log "${YELLOW}📋 Recommended next steps:${NC}"
log "1. Restart Crossplane pods to clear connection cache"
log "2. Monitor Crossplane claims for successful reconciliation" 
log "3. Apply permissive NetworkPolicies to prevent recurrence"
log ""
log "For permissive NetworkPolicy, apply this to your cluster:"
log "---"
cat << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-crossplane-communication
  namespace: crossplane-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
EOF
log "---"