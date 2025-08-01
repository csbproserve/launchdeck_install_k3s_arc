# DNS Debugging for K3s + Azure Arc

## Problem Pattern: Arc Setup Hangs in VM Environments

### Symptoms
- Azure Arc setup script hangs at step 13 (Arc connection) after 15-20 minutes
- Script appears to freeze during `az connectedk8s connect` command
- Common in VMware/VM environments on Rocky Linux, RHEL, CentOS

### Root Cause Analysis

#### 1. Initial Investigation
```bash
# Check Arc connection status from Azure perspective
az connectedk8s show --name <cluster> --resource-group <rg> --subscription <sub>
# Result: "provisioningState": "Succeeded", "connectivityStatus": "Connecting"
```

#### 2. Cluster Internal Issues
```bash
# Check Arc agent pods
kubectl get pods -n azure-arc
# Result: kube-aad-proxy stuck in ContainerCreating

# Investigate pod issues
kubectl describe pod -n azure-arc <kube-aad-proxy-pod>
# Result: MountVolume.SetUp failed for volume "kube-aad-proxy-tls" : secret "kube-aad-proxy-certificate" not found
```

#### 3. DNS Resolution Testing
```bash
# External DNS (usually works)
nslookup login.microsoftonline.com
nslookup management.azure.com

# Cluster internal DNS (fails in VM environments)
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local
# Result: FAILS - indicates CoreDNS forwarding issues
```

### Root Cause
**DNS forwarding problems in CoreDNS prevent Arc agents from generating certificates needed for authentication.**

## Proven Solution

### Manual DNS Fix (That Works)
```bash
#!/bin/bash
echo "🔧 Applying DNS fix for Arc agents..."

# Backup current config
kubectl get configmap coredns -n kube-system -o yaml > /tmp/coredns-backup.yaml

# Apply reliable DNS configuration
kubectl patch configmap coredns -n kube-system --type merge -p='
{
  "data": {
    "Corefile": ".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"
  }
}'

# Restart CoreDNS
echo "🔄 Restarting CoreDNS..."
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=90s

# Wait for DNS to stabilize
echo "⏳ Waiting for DNS to stabilize..."
sleep 30

# Test cluster DNS
echo "🧪 Testing cluster DNS..."
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local

# Restart Arc agents to pick up DNS changes
echo "🔄 Restarting Arc agents..."
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all

echo "✅ DNS fix applied. Arc agents should stabilize in 2-3 minutes."
```

### Key Technical Details
- **DNS Servers Used**: 1.1.1.1, 1.0.0.1 (Cloudflare - more reliable in VM environments than Google DNS)
- **Critical Timing**: 30-second wait after CoreDNS restart before testing
- **Full Agent Restart**: Both `rollout restart` and `delete pod` needed for full recovery

### Prevention & Best Practices
- Always test cluster internal DNS before Arc connection
- Use reliable DNS servers (1.1.1.1, 1.0.0.1) in VM environments
- Allow sufficient time for DNS propagation (30+ seconds)
- Monitor Arc agent logs for certificate-related errors
- Verify time synchronization before each Azure authentication