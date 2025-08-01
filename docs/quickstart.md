# Quick Start Guide

Get your K3s + Azure Arc cluster running in minutes with this step-by-step guide.

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] Linux system (RHEL 9, Rocky Linux, or CentOS)
- [ ] Internet connectivity
- [ ] Sudo privileges
- [ ] Azure service principal with Arc permissions
- [ ] Target Azure resource group created
- [ ] **Upstream firewall ports open** (see Network Requirements below)

### Network Requirements

Ensure the following ports are open in your upstream firewall/network infrastructure:

#### Outbound Internet Access (HTTPS/443)
- [ ] `get.k3s.io` - K3s installation
- [ ] `github.com` - Helm and component downloads
- [ ] `login.microsoftonline.com` - Azure authentication
- [ ] `management.azure.com` - Azure Resource Manager
- [ ] `*.servicebus.windows.net` - Arc agent communication
- [ ] DNS servers: `8.8.8.8`, `8.8.4.4` or `1.1.1.1`, `1.0.0.1`

#### K3s Cluster Ports (between cluster nodes)
- [ ] **6443/tcp** - Kubernetes API server
- [ ] **10250/tcp** - Kubelet API
- [ ] **8472/udp** - Flannel VXLAN
- [ ] **51820/udp** - Flannel Wireguard
- [ ] **51821/udp** - Flannel Wireguard (IPv6)

*Note: The script automatically configures local firewall rules, but upstream network firewalls must allow these connections.*

## Single-Node Deployment (Most Common)

### Step 1: Prepare Your Environment

```bash
# Set your Azure credentials
export CLIENT_ID="your-service-principal-id"
export CLIENT_SECRET="your-service-principal-secret"
export TENANT_ID="your-azure-tenant-id"
export SUB_ID="your-subscription-id"
export RESOURCE_GROUP="your-resource-group"
export CLUSTER_NAME="my-k3s-cluster"
```

### Step 2: Deploy the Cluster

```bash
# Basic deployment (uses Google DNS by default)
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME
```

### Step 3: Verify Deployment

```bash
# Check status
./setup-k3s-arc.sh --status

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

That's it! Your cluster is ready for GitOps deployments.

## VM Environment Deployment (Recommended)

If you're running on VMware or other VMs, use Cloudflare DNS for better reliability:

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

## Enterprise/Corporate Environment

For corporate networks with custom DNS:

```bash
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --dns-servers your-dns1,your-dns2 \
  --location your-region
```

## High-Availability Cluster

### Step 1: Deploy First Server Node

```bash
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $CLUSTER_NAME \
  --node-role server
```

### Step 2: Get Join Information

```bash
# The script automatically displays join commands in the "CLUSTER EXPANSION" section
# You can also view this information later with:
./setup-k3s-arc.sh --status --node-role server

# Or get the token manually if needed:
sudo cat /var/lib/rancher/k3s/server/node-token
```

### Step 3: Add Additional Server Nodes

```bash
# Run on additional server nodes
./setup-k3s-arc.sh \
  --node-role server \
  --server-ip 10.0.1.10 \
  --join-token K10abc123...::server:def456...
```

### Step 4: Add Worker Nodes

```bash
# Run on worker nodes
./setup-k3s-arc.sh \
  --node-role agent \
  --server-ip 10.0.1.10 \
  --join-token K10abc123...::server:def456...
```

## Verification Commands

### Check Overall Status
```bash
./setup-k3s-arc.sh --status
```

### Check Cluster Health
```bash
kubectl get nodes
kubectl get pods -A
kubectl top nodes  # If metrics are enabled
```

### Check Azure Arc Connection
```bash
az connectedk8s show \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --subscription $SUB_ID
```

### Check Flux (GitOps)
```bash
kubectl get pods -n flux-system
kubectl get gitrepository -A
kubectl get kustomization -A
```

## Common Next Steps

### 1. Deploy Your First Application

```bash
# Create a simple deployment
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=ClusterIP
```

### 2. Set Up GitOps

```bash
# Create a GitRepository resource for your app configs
kubectl apply -f - <<EOF
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: my-app-configs
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/your-org/your-app-configs
  ref:
    branch: main
EOF
```

### 3. Monitor Your Cluster

```bash
# Watch all pods
kubectl get pods -A -w

# Stream logs
kubectl logs -f deployment/nginx
```

## Troubleshooting Quick Fixes

### If Arc Connection Hangs
```bash
# Check DNS and apply fixes
./setup-k3s-arc.sh --diagnostics

# Apply DNS fix manually
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout restart deployment -n azure-arc
```

### If Service Principal Issues
```bash
# Diagnose service principal
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP
```

### If Time Sync Issues
```bash
# Fix time synchronization
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

### If Network Connectivity Issues
```bash
# Test outbound connectivity
curl -I https://get.k3s.io
curl -I https://login.microsoftonline.com
nslookup management.azure.com

# Check firewall rules
sudo firewall-cmd --list-ports
sudo firewall-cmd --list-services
```

### Reset and Start Over
```bash
# Reset state and try again
rm ~/.k3s-arc-setup-state
./setup-k3s-arc.sh --status  # Check what needs to be redone
```

## Performance Tips

### For VM Environments
- Use SSD storage for better performance
- Allocate at least 4GB RAM for stable operation
- Ensure VM has adequate CPU resources (2+ cores)

### For Production
- Use high-availability cluster setup
- Configure resource requests and limits
- Monitor cluster resource usage
- Set up cluster autoscaling if needed

## Security Best Practices

### Credentials
- Use environment variables for sensitive data
- Rotate service principal secrets regularly
- Use resource-group-scoped permissions

### Network
- Configure firewall rules appropriately
- Use network policies for pod communication
- Consider using private clusters for production

### Access
- Set up RBAC for user access
- Use Azure AD integration where possible
- Regular security audits

## What's Next?

After your cluster is running:

1. **Explore GitOps**: Set up Flux to manage your applications
2. **Add Monitoring**: Install Prometheus and Grafana
3. **Scale Your Cluster**: Add worker nodes as needed
4. **Deploy Applications**: Start deploying your workloads

---

*For more detailed configuration options, see [Configuration Guide](./configuration.md). For troubleshooting, see [Troubleshooting Guide](./troubleshooting.md).*