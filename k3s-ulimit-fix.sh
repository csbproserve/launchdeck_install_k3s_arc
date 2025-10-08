#!/bin/bash
#
# k3s-ulimit-fix.sh
#
# Fixes file descriptor (ulimit) issues for k3s clusters that commonly occur
# after disk space exhaustion events or in high-load environments.
#
# This script:
# 1. Increases system-wide file descriptor limits
# 2. Configures systemd service limits for k3s
# 3. Restarts k3s to apply changes
#
# Symptoms this fixes:
# - "Too many open files" errors in container logs (especially fluent-bit)
# - CrashLoopBackOff for Azure Arc agents (extension-manager, resource-sync-agent)
# - errno=24 errors in fluent-bit or other logging containers
#
# Usage:
#   sudo ./k3s-ulimit-fix.sh
#
# Author: LaunchDeck DevOps Team
# Date: 2025-10-08

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
   exit 1
fi

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}K3s File Descriptor Limit Fix${NC}"
echo -e "${GREEN}================================${NC}"
echo

# Backup existing limits.conf
LIMITS_CONF="/etc/security/limits.conf"
BACKUP_FILE="${LIMITS_CONF}.backup.$(date +%Y%m%d-%H%M%S)"

echo -e "${YELLOW}[1/5]${NC} Creating backup of ${LIMITS_CONF}..."
cp "$LIMITS_CONF" "$BACKUP_FILE"
echo -e "${GREEN}✓${NC} Backup created: $BACKUP_FILE"
echo

# Check current limits
echo -e "${YELLOW}[2/5]${NC} Current system limits:"
echo "  System max: $(cat /proc/sys/fs/file-max)"
echo "  Current user soft limit: $(su - ${SUDO_USER:-$(logname)} -c 'ulimit -Sn' 2>/dev/null || echo 'N/A')"
echo "  Current user hard limit: $(su - ${SUDO_USER:-$(logname)} -c 'ulimit -Hn' 2>/dev/null || echo 'N/A')"
echo

# Set system-wide limits
echo -e "${YELLOW}[3/5]${NC} Configuring system-wide file descriptor limits..."

# Remove any existing nofile entries to avoid conflicts
sed -i '/nofile/d' "$LIMITS_CONF"

# Add new limits at the end of file
cat >> "$LIMITS_CONF" << 'EOF'

# LaunchDeck k3s file descriptor limits
# Added by k3s-ulimit-fix.sh
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF

echo -e "${GREEN}✓${NC} System-wide limits configured"
echo

# Configure k3s service limits
echo -e "${YELLOW}[4/5]${NC} Configuring k3s service limits..."

K3S_SERVICE_DIR="/etc/systemd/system/k3s.service.d"
mkdir -p "$K3S_SERVICE_DIR"

cat > "${K3S_SERVICE_DIR}/limits.conf" << 'EOF'
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
EOF

# Reload systemd to pick up changes
systemctl daemon-reload

echo -e "${GREEN}✓${NC} k3s service limits configured"
echo

# Restart k3s
echo -e "${YELLOW}[5/5]${NC} Restarting k3s service..."
echo -e "${YELLOW}Warning:${NC} This will briefly interrupt cluster operations"
read -p "Press Enter to continue or Ctrl+C to abort..."

systemctl restart k3s

# Wait for k3s to be ready
echo -n "Waiting for k3s to be ready"
for i in {1..30}; do
    if systemctl is-active --quiet k3s; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo

# Verify the fix
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Verification${NC}"
echo -e "${GREEN}================================${NC}"
echo

if systemctl is-active --quiet k3s; then
    echo -e "${GREEN}✓${NC} k3s service is running"

    # Get k3s process limits
    K3S_PID=$(systemctl show k3s --property MainPID --value)
    if [[ -n "$K3S_PID" && "$K3S_PID" != "0" ]]; then
        K3S_NOFILE_LIMIT=$(cat /proc/$K3S_PID/limits | grep "open files" | awk '{print $4}')
        echo -e "${GREEN}✓${NC} k3s process file descriptor limit: $K3S_NOFILE_LIMIT"
    fi

    echo
    echo -e "${GREEN}New system limits:${NC}"
    echo "  System max: $(cat /proc/sys/fs/file-max)"

    echo
    echo -e "${GREEN}Fix applied successfully!${NC}"
    echo
    echo "Next steps:"
    echo "1. Monitor pods in azure-arc namespace:"
    echo "   kubectl get pods -n azure-arc"
    echo
    echo "2. Check for 'Too many open files' errors:"
    echo "   kubectl logs <pod-name> -n azure-arc --all-containers=true"
    echo
    echo "3. If pods are still in CrashLoopBackOff, delete them to force restart:"
    echo "   kubectl delete pod <pod-name> -n azure-arc"
    echo
else
    echo -e "${RED}✗${NC} k3s service failed to start"
    echo "Check logs with: journalctl -u k3s -n 50"
    exit 1
fi

echo -e "${YELLOW}Note:${NC} Changes to /etc/security/limits.conf will apply to new login sessions"
echo "      The k3s service has been restarted with the new limits immediately"
echo
