# Troubleshooting Guide

This comprehensive guide covers common issues, diagnostic approaches, and solutions for K3s + Azure Arc deployments.

## Quick Diagnostic Commands

```bash
# Overall system status
./setup-k3s-arc.sh --status

# Detailed diagnostics
./setup-k3s-arc.sh --diagnostics

# Service principal validation
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP

# DNS-specific troubleshooting
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i -- nslookup kubernetes.default.svc.cluster.local
```

## Common Issues by Category

### 1. Arc Connection Issues

#### Arc Connection Hangs (Most Common)

**Symptoms**:
- `az connectedk8s connect` hangs for 15-20+ minutes
- No progress or error messages
- Arc status shows "Connecting" in Azure portal

**Root Cause**: DNS issues preventing Arc agent certificate generation

**Solution**:
```bash
# Quick DNS fix
# Apply DNS fix via re-run with different DNS
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

#### Certificate Errors

**Symptoms**:
- Arc agents stuck in ContainerCreating
- Error: `secret "kube-aad-proxy-certificate" not found`
- MountVolume.SetUp failed for volume errors

**Diagnosis**:
```bash
# Check Arc agent status
kubectl get pods -n azure-arc

# Look for certificate errors
kubectl describe pods -n azure-arc | grep -A5 -B5 "certificate\|MountVolume"

# Check for certificate secrets
kubectl get secrets -n azure-arc | grep certificate
```

**Solution**: Apply DNS fix (see above) and wait for certificate generation

#### Time Synchronization Issues

**Symptoms**:
- Error: `Client assertion contains an invalid signature`
- AADSTS700024 errors
- Arc authentication failures

**Diagnosis**:
```bash
# Check time sync status
timedatectl status

# Check for large time differences
curl -sI https://www.google.com | grep -i date
```

**Solution**:
```bash
# Fix time synchronization
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# For chronyd systems
sudo chronyc makestep
sudo systemctl restart chronyd

# Restart Arc agents after time fix
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
```

### 2. Service Principal Issues

#### Authentication Failures

**Symptoms**:
- Azure login fails during setup
- Permission denied errors
- Invalid client credentials

**Diagnosis**:
```bash
# Test service principal
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP
```

**Solutions**:
```bash
# Verify credentials are correct
az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET -t $TENANT_ID

# Check role assignments
az role assignment list --assignee $CLIENT_ID --scope "/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP"

# Required role: "Kubernetes Cluster - Azure Arc Onboarding"
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Kubernetes Cluster - Azure Arc Onboarding" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RESOURCE_GROUP"
```

#### Resource Access Issues

**Symptoms**:
- Cannot access resource group
- Cannot list or create Arc resources
- Insufficient permissions errors

**Solution**:
```bash
# Verify resource group exists and is accessible
az group show --name $RESOURCE_GROUP --subscription $SUB_ID

# Check if resource group is in correct subscription
az account show --query id -o tsv
```

### 3. K3s Installation Issues

#### K3s Installation Failures

**Symptoms**:
- K3s installation script fails
- Service doesn't start
- Cannot access cluster

**Diagnosis**:
```bash
# Check K3s service status
systemctl status k3s

# Check K3s logs
journalctl -u k3s -f

# Test cluster access
kubectl get nodes
```

**Solutions**:
```bash
# Restart K3s service
sudo systemctl restart k3s

# Check firewall rules
sudo firewall-cmd --list-ports
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --reload

# Reset K3s if needed
sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s
# Re-run setup script
```

#### Node Join Failures

**Symptoms**:
- Additional nodes fail to join cluster
- Invalid join token errors
- Network connectivity issues

**Diagnosis**:
```bash
# Check join token information via status
./setup-k3s-arc.sh --status --node-role server

# Or manually check token validity
sudo cat /var/lib/rancher/k3s/server/node-token

# Test network connectivity between nodes
telnet $SERVER_IP 6443

# Check firewall rules on server node
sudo firewall-cmd --list-ports
```

**Solutions**:
```bash
# Get correct join token from server status
./setup-k3s-arc.sh --status --node-role server

# Or get token manually if needed
sudo cat /var/lib/rancher/k3s/server/node-token

# Ensure firewall ports are open
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --reload

# Use correct server IP (not localhost)
ip addr show | grep inet
```

### 4. DNS and Network Issues

#### External DNS Resolution

**Symptoms**:
- Cannot reach Azure services
- Package downloads fail
- Arc agents cannot authenticate

**Diagnosis**:
```bash
# Test external DNS
nslookup google.com
nslookup login.microsoftonline.com
nslookup management.azure.com

# Test HTTP connectivity
curl -I https://login.microsoftonline.com
curl -I https://management.azure.com
```

**Solutions**:
See [DNS Troubleshooting Guide](./dns-troubleshooting.md) for comprehensive DNS fixes.

#### Cluster Internal DNS

**Symptoms**:
- Pods cannot resolve services
- Arc agents fail certificate generation
- Internal service discovery broken

**Quick Fix**:
```bash
# Apply DNS fix
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'

kubectl rollout restart deployment/coredns -n kube-system
```

### 5. Flux Extension Issues

#### Flux Installation Failures

**Symptoms**:
- Flux extension installation times out
- Arc connection required error
- Flux pods not starting

**Prerequisites**: Arc connection must be fully working before Flux installation

**Diagnosis**:
```bash
# Verify Arc is fully connected
az connectedk8s show --name $CLUSTER_NAME --resource-group $RG --query "connectivityStatus"

# Check Arc agent health
kubectl get pods -n azure-arc

# Check for DNS/certificate issues
kubectl describe pods -n azure-arc | grep -i error
```

**Solution**:
```bash
# Ensure Arc agents are fully healthy first
kubectl get pods -n azure-arc
# All pods should be Running

# Wait for Arc stabilization if needed
sleep 120

# Retry Flux installation
az k8s-extension create \
  --cluster-name $CLUSTER_NAME \
  --resource-group $RG \
  --cluster-type connectedClusters \
  --extension-type microsoft.flux \
  --name flux
```

### 6. System-Level Issues

#### Time Synchronization

**Critical for**: Azure authentication, package verification, certificate generation

**Diagnosis**:
```bash
timedatectl status
chronyc sources -v  # If using chronyd
```

**Solution**:
```bash
# Enable time sync
sudo timedatectl set-ntp true
sudo systemctl enable systemd-timesyncd
sudo systemctl start systemd-timesyncd

# Or for chronyd
sudo systemctl enable chronyd
sudo systemctl start chronyd
sudo chronyc makestep
```

#### Firewall Configuration

**Symptoms**:
- Cannot reach K3s API
- Node communication failures
- Service discovery issues

**Solution**:
```bash
# Configure firewall for K3s
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=8472/udp
sudo firewall-cmd --permanent --add-port=51820/udp
sudo firewall-cmd --permanent --add-port=51821/udp
sudo firewall-cmd --reload
```

#### Resource Constraints

**Symptoms**:
- Pods stuck in Pending
- OOMKilled errors
- Performance issues

**Diagnosis**:
```bash
# Check resource usage
kubectl top nodes
kubectl top pods -A

# Check node capacity
kubectl describe nodes

# Check system resources
free -h
df -h
```

**Solutions**:
```bash
# Add more nodes if needed
./setup-k3s-arc.sh --node-role agent --server-ip $SERVER_IP --join-token $TOKEN

# Configure resource limits
kubectl patch deployment <deployment> -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container>","resources":{"requests":{"memory":"128Mi","cpu":"100m"}}}]}}}}'
```

## Architecture-Specific Issues

### ARM64/aarch64 Systems

**Common Issues**:
- Azure CLI compatibility
- Helm/kubectl architecture mismatches
- Arc agent stability

**Solutions**:
```bash
# Verify architecture compatibility
uname -m
./setup-k3s-arc.sh --diagnostics

# Use architecture-specific images
kubectl set image deployment/coredns coredns=registry.k8s.io/coredns/coredns:v1.10.1 -n kube-system
```

### VM-Specific Issues

#### VMware
- DNS forwarding problems (use Cloudflare DNS)
- Time sync drift (enable VMware Tools)
- NAT networking complications

#### Cloud VMs
- Metadata service conflicts
- Security group/firewall rules
- Instance type limitations

## Recovery Procedures

### Complete Reset
```bash
# Reset setup state
rm ~/.k3s-arc-setup-state

# Check what needs to be redone
./setup-k3s-arc.sh --status

# Remove Arc connection if needed
az connectedk8s delete --name $CLUSTER_NAME --resource-group $RG

# Uninstall K3s if needed
sudo systemctl stop k3s
sudo rm -rf /var/lib/rancher/k3s
sudo rm /usr/local/bin/k3s /usr/local/bin/kubectl

# Re-run setup
./setup-k3s-arc.sh [parameters]
```

### Arc Agent Recovery
```bash
# Emergency Arc agent restart
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all

# Wait for recovery
sleep 120
kubectl get pods -n azure-arc
```

### DNS Recovery
```bash
# Emergency DNS fix
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'

kubectl rollout restart deployment/coredns -n kube-system
sleep 30
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
```

## Prevention Strategies

### Pre-deployment Checklist
- [ ] Verify system requirements
- [ ] Test network connectivity
- [ ] Validate service principal permissions
- [ ] Check time synchronization
- [ ] Ensure firewall ports are open

### Best Practices
- Use reliable DNS servers (1.1.1.1, 1.0.0.1 for VMs)
- Deploy with verbose mode for troubleshooting
- Monitor Arc agent health regularly
- Keep system time synchronized
- Use resource-group-scoped service principals

### Monitoring
```bash
# Regular health checks
./setup-k3s-arc.sh --status

# DNS health monitoring
kubectl run dns-monitor --image=busybox:1.35 --restart=Never --rm -i -- nslookup kubernetes.default.svc.cluster.local

# Arc connectivity monitoring
az connectedk8s show --name $CLUSTER_NAME --resource-group $RG --query "connectivityStatus"
```

## Getting Help

### Built-in Diagnostics
```bash
# Comprehensive system diagnostics
./setup-k3s-arc.sh --diagnostics

# Service principal validation
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP

# Current setup status
./setup-k3s-arc.sh --status
```

### Log Collection
```bash
# K3s logs
journalctl -u k3s --since "1 hour ago" > k3s-logs.txt

# Arc agent logs
kubectl logs -n azure-arc -l app.kubernetes.io/component=connect-agent > arc-logs.txt

# CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns > dns-logs.txt
```

### Additional Resources
- [DNS Troubleshooting Guide](./dns-troubleshooting.md)
- [Diagnostics Reference](./diagnostics.md)
- [Environment Notes](./environment-notes.md)

---

*For DNS-specific issues, see [DNS Troubleshooting Guide](./dns-troubleshooting.md). For command references, see [Command Reference](./command-reference.md).*