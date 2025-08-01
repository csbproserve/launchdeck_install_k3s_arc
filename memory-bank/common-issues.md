# Common Issues & Quick Fixes

## Error Messages & Solutions

### Arc Agent Certificate Issues

#### Error: `secret "kube-aad-proxy-certificate" not found`
```
Events:
  Warning  FailedMount  5m (x12 over 15m)  kubelet  MountVolume.SetUp failed for volume "kube-aad-proxy-tls" : secret "kube-aad-proxy-certificate" not found
```

**Root Cause**: DNS issues preventing certificate generation  
**Quick Fix**: Apply DNS fix and restart Arc agents

```bash
# Emergency DNS + Arc restart
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
```

#### Error: `Client assertion contains an invalid signature`
```
AADSTS700024: Client assertion contains an invalid signature. [Reason - The key was not found., Thumbprint of key used by client: 'XXXXX']
```

**Root Cause**: Time synchronization issues  
**Quick Fix**: Fix time sync and restart Arc agents

```bash
# Fix time synchronization
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
sleep 10

# Restart Arc agents
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
```

### DNS Resolution Issues

#### Error: `nslookup: can't resolve 'kubernetes.default.svc.cluster.local'`
**Symptoms**: Cluster internal DNS failing  
**Impact**: Arc agents cannot generate certificates

**Quick Test**:
```bash
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local
```

**Quick Fix**: Apply CoreDNS patch
```bash
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'
kubectl rollout restart deployment/coredns -n kube-system
```

### Arc Connection Hangs

#### Symptom: `az connectedk8s connect` hangs with no output
**Duration**: 15-20+ minutes with no progress  
**Environment**: Common in VMware/VM setups

**Quick Diagnosis**:
```bash
# Check Arc agent status
kubectl get pods -n azure-arc

# Check for certificate issues
kubectl describe pods -n azure-arc | grep -A5 -B5 "certificate\|MountVolume"

# Test DNS
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local
```

**Quick Fix**: DNS fix + Arc restart (see DNS section above)

### Flux Extension Issues

#### Error: Flux extension fails to install
**Prerequisites**: Arc connection must be fully working  
**Common Cause**: Arc agents not fully stabilized

**Quick Check**:
```bash
# Verify Arc is fully connected
az connectedk8s show --name <cluster> --resource-group <rg> --subscription <sub> --query "connectivityStatus"

# Should return: "Connected"
```

**Quick Fix**: Wait for Arc stabilization
```bash
# Wait for all Arc pods to be running
kubectl get pods -n azure-arc -w

# Retry Flux installation after 2-3 minutes
```

## Emergency Recovery Commands

### Complete Reset & Recovery
```bash
#!/bin/bash
echo "🚨 Emergency Arc Recovery"

# Step 1: Fix DNS
echo "🔧 Applying DNS fix..."
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}' 

# Step 2: Restart CoreDNS
echo "🔄 Restarting CoreDNS..."
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=90s

# Step 3: Wait for DNS stabilization
echo "⏳ Waiting for DNS to stabilize..."
sleep 30

# Step 4: Test DNS
echo "🧪 Testing DNS..."
if kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local; then
    echo "✅ DNS working"
else
    echo "❌ DNS still broken"
fi

# Step 5: Restart Arc agents
echo "🔄 Restarting Arc agents..."
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all

# Step 6: Monitor recovery
echo "👀 Monitoring Arc agents..."
sleep 60
kubectl get pods -n azure-arc

echo "✅ Emergency recovery complete"
```

### Quick Health Check
```bash
#!/bin/bash
echo "=== Arc Health Check ==="

# DNS Test
echo "🧪 Testing DNS..."
if kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
    echo "✅ DNS: Working"
else
    echo "❌ DNS: Failed"
fi

# Arc Pods
echo "🖥️ Arc Pods:"
kubectl get pods -n azure-arc --no-headers | awk '{print $3}' | sort | uniq -c

# Certificate Secrets
echo "🔐 Certificate Secrets:"
kubectl get secrets -n azure-arc | grep certificate | wc -l

# Arc Connection
echo "🔗 Arc Connection:"
az connectedk8s show --name <cluster> --resource-group <rg> --subscription <sub> --query "connectivityStatus" -o tsv 2>/dev/null || echo "Unknown"
```

## Troubleshooting Decision Tree

### 1. Arc Connection Hangs
```
Is DNS working? → kubectl run dns-test...
├─ NO: Apply DNS fix
└─ YES: Check time sync → timedatectl status
   ├─ BAD: Fix time sync
   └─ GOOD: Check Arc logs
```

### 2. Pods Stuck in ContainerCreating
```
Check for certificate errors → kubectl describe pods...
├─ Certificate errors found: Apply DNS fix
└─ No certificate errors: Check node resources
```

### 3. DNS Test Fails
```
External DNS working? → nslookup google.com
├─ NO: Host DNS issue
└─ YES: CoreDNS issue → Apply DNS fix
```

### 4. Time Sync Issues
```
Check sync status → timedatectl status
├─ Not synchronized: Enable NTP
└─ Synchronized: Check Azure token validity
```

## Prevention Checklist

### Before Arc Connection
- [ ] Verify DNS resolution works
- [ ] Confirm time synchronization
- [ ] Check firewall rules
- [ ] Ensure sufficient resources

### During Arc Connection
- [ ] Monitor pod creation progress
- [ ] Watch for certificate errors
- [ ] Check DNS stability
- [ ] Monitor connection logs

### After Arc Connection
- [ ] Verify all pods Running
- [ ] Test DNS resolution
- [ ] Check certificate secrets
- [ ] Validate Azure connectivity