# DNS Troubleshooting Guide

DNS issues are the most common cause of Azure Arc connection problems, especially in VM environments. This guide provides comprehensive DNS troubleshooting and automatic fixes.

## Quick DNS Fix

If you're experiencing Arc connection hangs or certificate errors, try this immediate fix:

```bash
# Apply automatic DNS fix (requires full parameters)
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers 1.1.1.1,1.0.0.1

# Or apply manually
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
```

## Understanding DNS Issues

### Root Cause: VM DNS Forwarding Problems

**The Problem**: VM environments (especially VMware) frequently experience DNS forwarding issues that prevent Azure Arc agents from generating certificates needed for authentication.

**The Impact**: 
- Arc connection hangs indefinitely (15-20+ minutes)
- Arc agents stuck in ContainerCreating state
- Certificate secrets not generated
- Flux extension installation fails

### Why This Happens

1. **VM Network Isolation**: VMs may not properly forward DNS queries to upstream servers
2. **Corporate DNS Servers**: May not reliably resolve external Azure services
3. **NAT Networking**: Can interfere with DNS resolution paths
4. **Time Sync Issues**: Affect certificate generation timing

## DNS Diagnostic Commands

### Test External DNS Resolution
```bash
# Test basic internet DNS
nslookup google.com

# Test Azure services (critical for Arc)
nslookup login.microsoftonline.com
nslookup management.azure.com

# Test container registries
nslookup mcr.microsoft.com
```

### Test Cluster Internal DNS
```bash
# Test cluster DNS from within cluster
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local

# Test simpler internal resolution
kubectl run dns-simple --image=busybox:1.35 --restart=Never --rm -i --timeout=20s -- nslookup kubernetes.default
```

### Check CoreDNS Health
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS configuration
kubectl get configmap coredns -n kube-system -o yaml

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

## Symptoms and Diagnosis

### Arc Connection Hangs
**Symptoms**:
- `az connectedk8s connect` command hangs for 15-20+ minutes
- No progress indicators or error messages
- Arc shows "Connecting" status in Azure portal

**Diagnosis**:
```bash
# Check Arc agent status
kubectl get pods -n azure-arc

# Look for certificate errors
kubectl describe pods -n azure-arc | grep -A5 -B5 "certificate\|MountVolume"

# Verify Azure connectivity from cluster
kubectl run azure-test --image=busybox:1.35 --restart=Never --rm -i -- nslookup login.microsoftonline.com
```

### Certificate Generation Failures
**Symptoms**:
- Arc agents stuck in ContainerCreating
- Error: `secret "kube-aad-proxy-certificate" not found`
- MountVolume.SetUp failed errors

**Diagnosis**:
```bash
# Check for certificate secrets
kubectl get secrets -n azure-arc | grep certificate

# Check pod events for certificate errors
kubectl describe pod -n azure-arc <pod-name> | grep -A10 Events
```

## DNS Fix Solutions

### Recommended DNS Servers

#### Cloudflare DNS (Recommended for VMs)
```bash
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers 1.1.1.1,1.0.0.1
```
- **Pros**: Fastest, most reliable in VM environments
- **Best for**: VMware, VirtualBox, Hyper-V environments

#### Google DNS (Default)
```bash
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers 8.8.8.8,8.8.4.4
```
- **Pros**: Widely supported, good general performance
- **Best for**: Physical servers, cloud VMs

#### OpenDNS
```bash
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers 208.67.222.222,208.67.220.220
```
- **Pros**: Good enterprise features
- **Best for**: Corporate environments with filtering needs

#### Corporate DNS
```bash
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers your-dns1,your-dns2
```
- **Pros**: Complies with corporate policies
- **Note**: May require additional configuration for external Azure services

### Manual DNS Fix Process

If automatic fixes don't work, apply manually:

#### 1. Backup Current Configuration
```bash
kubectl get configmap coredns -n kube-system -o yaml > /tmp/coredns-backup.yaml
```

#### 2. Apply DNS Fix
```bash
# Update CoreDNS with reliable DNS servers
kubectl patch configmap coredns -n kube-system --type merge -p='
{
  "data": {
    "Corefile": ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"
  }
}'
```

#### 3. Restart CoreDNS
```bash
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=90s
```

#### 4. Wait for DNS Stabilization
```bash
# Wait for DNS to stabilize (critical timing)
sleep 30
```

#### 5. Test DNS Fix
```bash
kubectl run dns-fix-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local
```

#### 6. Restart Arc Agents
```bash
# Full Arc agent restart to pick up DNS changes
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all

# Wait for agents to stabilize
sleep 60
```

## Environment-Specific Solutions

### VMware Environments
**Common Issues**:
- VM DNS forwarding failures
- Time synchronization drift
- NAT networking complications

**Solutions**:
```bash
# Use Cloudflare DNS
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers 1.1.1.1,1.0.0.1

# Ensure VMware Tools time sync
sudo systemctl enable vmtoolsd
```

### Corporate Networks
**Common Issues**:
- Firewall blocking Azure services
- Corporate DNS not resolving external services
- Proxy configurations

**Solutions**:
```bash
# Use corporate DNS with fallback
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers corporate-dns1,1.1.1.1

# Test Azure service connectivity
curl -I https://login.microsoftonline.com
curl -I https://management.azure.com
```

### Cloud Environments

#### Azure VMs
- Generally good DNS compatibility
- Use Azure-provided DNS when possible
- Consider Azure Private DNS for internal services

#### AWS EC2
- Instance metadata service can interfere
- Use VPC DNS settings
- Test cross-cloud connectivity carefully

## Prevention Strategies

### Pre-deployment Testing
```bash
# Test DNS before deployment
nslookup login.microsoftonline.com
nslookup management.azure.com

# Test Azure CLI connectivity
az account list-locations --output table
```

### Deployment Best Practices
```bash
# Use reliable DNS from start
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers 1.1.1.1,1.0.0.1 \
  --verbose
```

### Monitoring DNS Health
```bash
# Regular DNS health checks
kubectl run dns-monitor --image=busybox:1.35 --restart=Never --rm -i -- nslookup kubernetes.default.svc.cluster.local

# Check CoreDNS metrics
kubectl top pods -n kube-system -l k8s-app=kube-dns
```

## Recovery from DNS Issues

### Emergency Recovery
```bash
#!/bin/bash
echo "🚨 Emergency Arc DNS Recovery"

# Step 1: Fix DNS
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'

# Step 2: Restart DNS
kubectl rollout restart deployment/coredns -n kube-system
sleep 30

# Step 3: Test DNS
kubectl run dns-emergency-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local

# Step 4: Restart Arc agents
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
sleep 60

echo "✅ Emergency recovery complete"
```

### Complete Reset
```bash
# If all else fails, reset DNS configuration
kubectl delete configmap coredns -n kube-system
kubectl rollout restart deployment/coredns -n kube-system

# Wait for K3s to recreate default configuration
sleep 60

# Then apply fix
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers 1.1.1.1,1.0.0.1
```

## Success Validation

### Before Fix (Broken State)
- Arc connection hangs >15 minutes
- Arc agents stuck in ContainerCreating
- No certificate secrets generated
- DNS test fails: `nslookup: can't resolve 'kubernetes.default.svc.cluster.local'`

### After Fix (Working State)
- Arc connection completes in 5-10 minutes
- All Arc agents Running (11-12 pods)
- Certificate secrets present
- DNS test succeeds: `kubernetes.default.svc.cluster.local` resolves correctly

### Monitoring Commands
```bash
# Quick health check
kubectl get pods -n azure-arc --no-headers | grep -v Running | wc -l
# Should return 0 for healthy system

# Certificate check
kubectl get secrets -n azure-arc | grep certificate
# Should show certificate secrets

# Arc connectivity
az connectedk8s show --name $CLUSTER_NAME --resource-group $RG --query "connectivityStatus"
# Should return "Connected"
```

---

*For more troubleshooting, see [Troubleshooting Guide](./troubleshooting.md). For command references, see [Diagnostics](./diagnostics.md).*