# Debugging Patterns: Systematic Problem Diagnosis

## Sudo Credential Inheritance Patterns

### Working Pattern: Consolidated Commands
**Example**: Time synchronization function (Lines 340-374)
```bash
sudo bash -c 'timedatectl set-ntp true; systemctl restart systemd-timesyncd; systemctl restart chronyd'
```
**Why it works**: Single sudo session maintains credential context for all commands

### Failing Pattern: Individual Commands via execute_deployment_step
**Example**: Package installation (Lines 1375, 1379)
```bash
execute_deployment_step "sudo dnf update -y" "Updating system packages"
```
**Why it fails**: Each `eval` call creates a subprocess that doesn't inherit cached credentials

### Root Cause: Subprocess Credential Context
- **Background keep-alive**: Works correctly (maintains sudo timestamp)
- **Problem**: `execute_deployment_step` function creates execution contexts that can't access cached credentials
- **Key insight**: Not about quoting or command structure, but subprocess credential inheritance

## DNS Debugging Architecture

### Component Relationship Flow
```
VM DNS Issues → CoreDNS Failures → Arc Certificate Problems → Connection Hangs
```

### Detection Patterns
1. **Cluster Internal DNS Test**:
   ```bash
   kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local
   ```

2. **Arc Agent Certificate Issues**:
   ```bash
   kubectl describe pods -n azure-arc | grep -A5 -B5 "certificate\|MountVolume"
   ```

3. **Connection Hang Indicators**:
   - `az connectedk8s connect` runs 15+ minutes with no output
   - Arc agents stuck in ContainerCreating state
   - Certificate secrets missing or failed to mount

### Fix Pattern: DNS + Arc Agent Restart
```bash
# 1. Fix CoreDNS configuration
kubectl patch configmap coredns -n kube-system --type merge -p='...'

# 2. Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# 3. Wait for DNS stabilization (critical timing)
sleep 30

# 4. Restart Arc agents (both methods needed)
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all

# 5. Wait for certificate regeneration
sleep 60
```

## K3s + Arc Integration Patterns

### Critical Dependencies
1. **DNS Resolution**: Must work before Arc connection
2. **Time Synchronization**: Required for Azure certificate validation
3. **Network Connectivity**: Outbound HTTPS access to Azure endpoints
4. **Certificate Generation**: Depends on working DNS + time sync

### Environment-Specific Issues
- **VMware environments**: DNS forwarding frequently broken
- **Rocky Linux/RHEL**: SELinux and firewall considerations
- **Enterprise networks**: Proxy and firewall restrictions

## Timing Patterns

### DNS Stabilization
- **Minimum wait**: 30 seconds after CoreDNS restart
- **Certificate generation**: 2-3 minutes after DNS fix
- **Arc agent ready**: 3-5 minutes total recovery time

### Sudo Credential Timing
- **Background keep-alive**: Refreshes every 4 minutes (280 seconds)
- **Race condition**: 1-second delay needed after initial sudo authentication
- **Subprocess inheritance**: Immediate - no timing dependency

## Error Pattern Recognition

### Arc Connection Hangs
**Symptoms**: 
- Command runs 15+ minutes with no output
- No error messages
- Azure shows "Connecting" status

**Root Cause**: DNS resolution failures preventing certificate generation

### Certificate Mount Failures
**Symptoms**:
```
MountVolume.SetUp failed for volume "kube-aad-proxy-tls" : secret "kube-aad-proxy-certificate" not found
```
**Root Cause**: DNS issues preventing certificate generation

### Multiple Sudo Prompts
**Symptoms**:
- Password prompts during deployment steps
- Background keep-alive process running successfully
- Time sync works but package installation fails

**Root Cause**: Subprocess credential inheritance in `execute_deployment_step` function

## Bash Script UX Patterns

### Sudo Context Variable Expansion
**Problem**: Using `~/.kube/config` in sudo commands creates files in root's home directory
**Root Cause**: In sudo context, `~` expands to root's home (`/root/`), not user's home
**Solution Pattern**:
```bash
# WRONG - creates file in /root/.kube/config
sudo mkdir -p ~/.kube && sudo cp file ~/.kube/config

# CORRECT - creates file in user's home directory
sudo mkdir -p $HOME/.kube && sudo cp file $HOME/.kube/config
```
**Application**: Always use `$HOME` for user file operations in sudo commands

### Visual Hierarchy in Progress Messages
**Pattern**: Maintain logical workflow hierarchy, not just visual grouping
**Implementation**:
```bash
# Main actions (5 spaces)
echo "     ❄️ Applying DNS fix for Arc connectivity..."
echo "     ❄️ Cluster DNS now working correctly"
echo "     ❄️ Restarting Arc agents..."

# Sub-steps of main actions (6 spaces)
echo "      ❄️ Updating CoreDNS with DNS servers..."
echo "      ✅ CoreDNS configmap updated..."
echo "      ✅ Restarting CoreDNS deployment..."
```
**Key Logic**: Status validation and separate processes are main-level, not sub-steps

### ANSI Escape Sequence Handling
**Problem**: Heredoc doesn't interpret escape sequences in variables
**Failing Pattern**:
```bash
usage() {
    cat << EOF
${bold}Usage:${reset} script.sh [options]
EOF
}
```
**Working Pattern**:
```bash
usage() {
    echo -e "${bold}Usage:${reset} script.sh [options]"
    echo -e "${bold}Options:${reset}"
    echo -e "  --help    Show this help"
}
```
**Reason**: `cat << EOF` outputs literally, `echo -e` interprets escape sequences

### DNS Troubleshooting Output Control
**Problem**: Error functions automatically showing DNS guides when not relevant
**Pattern**: Separate error context from automatic troubleshooting
**Solution**:
```bash
# Remove conditional logic that auto-displays DNS guide
enterprise_error() {
    local exit_code=$1
    local context="$2"
    
    echo "❌ Error: $context"
    echo "💡 For troubleshooting, run: $0 --verbose --mode status"
    # Removed: if [[ "$context" == *"Arc"* ]]; then show_dns_guide; fi
}
```

## Diagnostic Command Patterns

### Quick Health Check
```bash
# DNS Test
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local

# Arc Pod Status
kubectl get pods -n azure-arc

# Certificate Issues
kubectl describe pods -n azure-arc | grep -A5 -B5 certificate

# Time Sync
timedatectl status | grep synchronized
```

### Emergency Recovery
```bash
# Complete DNS + Arc restart sequence
kubectl patch configmap coredns -n kube-system --type merge -p='...'
kubectl rollout restart deployment/coredns -n kube-system
sleep 30
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
sleep 60
```

## Prevention Patterns

### Proactive DNS Fix
- Always test cluster DNS before Arc connection attempts
- Apply DNS fix in VM environments preemptively
- Monitor DNS stability during deployment

### Credential Management
- Use consolidated sudo commands where possible
- Minimize subprocess creation in credential-sensitive operations
- Test credential inheritance patterns before implementation

## Join Token Display Debugging Pattern

### Problem Recognition
**Symptom**: Join token not showing after successful server deployment or in status mode
**Common Indicators**:
- Server deployment completes successfully
- `--status --node-role server` shows no join token
- Token file exists at `/var/lib/rancher/k3s/server/node-token`

### Root Cause Analysis
**File Permission Issue**: Standard file existence test fails
```bash
# This fails even when file exists due to permissions
[[ -f /var/lib/rancher/k3s/server/node-token ]]
```

**Credential Context Issue**: Token access requires sudo but breaks single-prompt UX
```bash
# This works but prompts for password again
sudo cat /var/lib/rancher/k3s/server/node-token
```

### Solution Pattern: Secure Token Access
**Deployment Mode** (with stored credentials):
```bash
if [[ -n "$SUDO_PASSWORD" ]] && echo "$SUDO_PASSWORD" | sudo -S test -f /var/lib/rancher/k3s/server/node-token 2>/dev/null; then
    JOIN_TOKEN=$(echo "$SUDO_PASSWORD" | sudo -S cat /var/lib/rancher/k3s/server/node-token 2>/dev/null)
fi
```

**Status Mode** (graceful fallback):
```bash
if sudo -n test -f /var/lib/rancher/k3s/server/node-token 2>/dev/null; then
    JOIN_TOKEN=$(sudo -n cat /var/lib/rancher/k3s/server/node-token 2>/dev/null)
else
    # Show helpful message instead of failing silently
    echo "Available (run: sudo cat /var/lib/rancher/k3s/server/node-token)"
fi
```

### Key Technical Insights
1. **File existence tests fail with permissions**: Use `sudo test -f` instead of `[[ -f ]]`
2. **Maintain credential context**: Use stored password with `sudo -S` during deployment
3. **Graceful degradation**: Provide helpful fallback in status mode
4. **Single-prompt preservation**: Never use bare `sudo` in credential-managed scripts