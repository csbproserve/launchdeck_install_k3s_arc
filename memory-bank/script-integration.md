# Script Integration Patterns

## Time Sync Re-verification

### Pattern: Always Re-verify Before Azure Operations
```bash
# Always verify time sync before Azure operations, even if previously marked complete
if is_completed "time_sync_configured"; then
    log "Re-verifying system time synchronization for Azure authentication..."
    sync_status=$(timedatectl status 2>/dev/null | grep "synchronized:" | awk '{print $2}' || echo "unknown")
    
    if [[ "$sync_status" != "yes" ]]; then
        warn "Time synchronization status changed - re-running time sync"
        # Remove completion marker and re-run
        sed -i '/^time_sync_configured=completed$/d' "$STATE_FILE" 2>/dev/null || true
    fi
fi
```

## Automatic DNS Detection & Fix

### Enhanced Health Check Pattern
```bash
# Enhanced health check before Flux installation
DNS_ISSUES=false
ARC_CERTIFICATE_ISSUES=false

# Test cluster internal DNS
if ! kubectl run dns-test-quick --image=busybox:1.35 --restart=Never --rm -i --timeout=20s -- nslookup kubernetes.default >/dev/null 2>&1; then
    DNS_ISSUES=true
fi

# Check Arc agent certificate issues
CERTIFICATE_ISSUES=$(kubectl describe pods -n azure-arc 2>/dev/null | grep -c "certificate.*not found\|failed.*certificate\|MountVolume.*failed" || echo "0")
if [[ $CERTIFICATE_ISSUES -gt 0 ]]; then
    ARC_CERTIFICATE_ISSUES=true
    DNS_ISSUES=true  # Certificate issues usually indicate DNS problems
fi

# Apply automatic fix
if [[ "$DNS_ISSUES" == "true" ]] && [[ "$FIX_DNS" == "true" ]]; then
    apply_dns_fix
fi
```

### DNS Fix Function Template
```bash
apply_dns_fix() {
    echo "${WRENCH} Applying DNS fix for Arc connectivity..."
    
    # Backup current config
    kubectl get configmap coredns -n kube-system -o yaml > /tmp/coredns-backup.yaml
    
    # Apply reliable DNS configuration
    kubectl patch configmap coredns -n kube-system --type merge -p='
    {
      "data": {
        "Corefile": ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"
      }
    }'
    
    if [[ $? -eq 0 ]]; then
        echo "        ${CHECK} CoreDNS configmap updated with DNS servers: 1.1.1.1, 1.0.0.1"
    else
        echo "        ${CROSS} Failed to update CoreDNS configmap"
        return 1
    fi
    
    # Restart CoreDNS
    verbose_log "Restarting CoreDNS deployment..."
    kubectl rollout restart deployment/coredns -n kube-system
    kubectl rollout status deployment/coredns -n kube-system --timeout=90s >/dev/null 2>&1
    
    # Wait for DNS to stabilize
    verbose_log "Waiting for DNS to stabilize..."
    sleep 30
    
    # Test DNS fix
    verbose_log "Testing DNS fix..."
    if kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
        echo "        ${CHECK} Cluster DNS now working correctly"
    else
        echo "        ${CROSS} DNS test still failing after fix"
        return 1
    fi
    
    # Restart Arc agents
    echo "        ${REFRESH} Restarting Arc agents to resolve certificate issues..."
    kubectl rollout restart deployment -n azure-arc >/dev/null 2>&1
    kubectl delete pod -n azure-arc --all >/dev/null 2>&1
    
    verbose_log "Waiting 60 seconds for Arc agents to stabilize..."
    sleep 60
    
    echo "        ${CHECK} DNS fix completed successfully"
    return 0
}
```

## Detection Logic Patterns

### Arc Agent Health Detection
```bash
check_arc_agent_health() {
    local not_ready_count=$(kubectl get pods -n azure-arc --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l || echo "0")
    local certificate_issues=$(kubectl describe pods -n azure-arc 2>/dev/null | grep -c "certificate.*not found\|failed.*certificate\|MountVolume.*failed" || echo "0")
    
    echo "${not_ready_count}:${certificate_issues}"
}
```

### DNS Connectivity Testing
```bash
test_cluster_dns() {
    if kubectl run dns-test-quick --image=busybox:1.35 --restart=Never --rm -i --timeout=20s -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
        return 0  # DNS working
    else
        return 1  # DNS failed
    fi
}
```

## Error Handling Patterns

### Graceful Degradation
```bash
if ! apply_dns_fix; then
    warn "DNS fix failed - continuing with manual intervention required"
    echo "Manual DNS fix may be needed. See memory-bank/dns-debugging.md"
    return 1
fi
```

### Retry Logic
```bash
retry_arc_connection() {
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if test_arc_connectivity; then
            return 0
        fi
        
        warn "Arc connectivity test failed (attempt $attempt/$max_attempts)"
        if [[ $attempt -lt $max_attempts ]]; then
            sleep 30
        fi
        ((attempt++))
    done
    
    return 1
}

## Offline Component Integration Patterns

### Offline Component Detection System
```bash
# Master offline component validation function
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
```

### Individual Component Validation Patterns
```bash
# Helm validation with version checking
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

# kubectl validation with client version check
validate_offline_kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
        if kubectl version --client >/dev/null 2>&1; then
            local kubectl_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo "unknown")
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

# Azure CLI validation with both system and user-local paths
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
```

### Offline Mode Step Integration
```bash
# Dynamic step counting based on offline mode
if [[ "$OFFLINE" == "true" ]]; then
    TOTAL_STEPS=8  # Skip system_update, packages_installed, k3s_installed, azure_cli_installed, helm_installed
    if [[ "$ENABLE_REMOTE_MGMT" == "true" ]]; then
        TOTAL_STEPS=9
    fi
    if [[ "$VERBOSE" != "true" ]] && [[ "$QUIET" != "true" ]]; then
        log "Using offline components (skipping system updates, packages, K3s installation, Azure CLI installation, and Helm installation)"
    fi
else
    TOTAL_STEPS=14  # Full deployment
    if [[ "$ENABLE_REMOTE_MGMT" == "true" ]]; then
        TOTAL_STEPS=15
    fi
fi

# Conditional step execution pattern
if [[ "$OFFLINE" == "true" ]]; then
    verbose_log "Skipping Helm installation (offline mode - Helm should be pre-installed)"
    # Mark as completed since it should already be installed via offline bundle
    if ! is_completed "helm_installed"; then
        mark_completed "helm_installed"
    fi
else
    # Normal online installation logic
    if pre_execute_steps "helm_installed" "Installing Helm"; then
        # ... installation code ...
    fi
fi
```

### Offline Mode Error Handling
```bash
# Comprehensive error message for missing offline components
if [[ "$OFFLINE" == "true" ]] && ! detect_offline_components; then
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
```

### Offline Status Display Integration
```bash
# Header display with offline mode indicator
if [[ "$OFFLINE" == "true" ]]; then
    echo -e "   ${BOLD}Mode:${NC} ${FOLDER} Offline (using pre-installed components)"
fi
```
```

## Integration Points

### Pre-Arc Connection Hook
```bash
# Before attempting Arc connection
if [[ "$ENABLE_DNS_FIX" == "true" ]]; then
    health_check=$(check_arc_agent_health)
    not_ready_count=$(echo "$health_check" | cut -d: -f1)
    certificate_issues=$(echo "$health_check" | cut -d: -f2)
    
    if [[ $certificate_issues -gt 0 ]] || ! test_cluster_dns; then
        echo "      ${WRENCH} Arc agents need DNS fix ($not_ready_count pods not ready, $certificate_issues certificate issues)"
        apply_dns_fix
    fi
fi
```

### Post-Installation Validation
```bash
# After Arc connection completes
validate_arc_deployment() {
    local max_wait=300  # 5 minutes
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local running_pods=$(kubectl get pods -n azure-arc --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
        
        if [[ $running_pods -ge 10 ]]; then  # Expect ~12 pods typically
            return 0
        fi
        
        sleep 15
        elapsed=$((elapsed + 15))
    done
    
    return 1
}