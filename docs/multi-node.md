# Multi-Node Cluster Setup

This guide covers deploying high-availability K3s clusters with multiple server and agent nodes, including load balancing, etcd clustering, and best practices for production environments.

## Overview

K3s supports two cluster architectures:
- **Single-server**: One server node (default setup)
- **High-availability**: Multiple server nodes with embedded etcd

## High-Availability Architecture

### Cluster Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Load Balancer                            │
│                  (External/Optional)                        │
└─────────────────────┬───────────────────────────────────────┘
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
┌───▼───┐         ┌───▼───┐         ┌───▼───┐
│Server1│         │Server2│         │Server3│
│(etcd) │◄────────┤(etcd) │────────►│(etcd) │
└───┬───┘         └───┬───┘         └───┬───┘
    │                 │                 │
    └─────────────────┼─────────────────┘
                      │
    ┌─────────────────┼─────────────────┐
    │                 │                 │
┌───▼───┐         ┌───▼───┐         ┌───▼───┐
│Agent1 │         │Agent2 │         │Agent3 │
└───────┘         └───────┘         └───────┘
```

### Minimum Requirements for HA

- **Server nodes**: 3 (odd number required for etcd quorum)
- **Agent nodes**: 0 or more (workload nodes)
- **Resources**: 2 CPU, 4GB RAM per server node minimum
- **Network**: All nodes must communicate on required ports

## Step-by-Step HA Deployment

### Step 1: Deploy First Server Node

```bash
./setup-k3s-arc.sh \
  --client-id "12345678-1234-1234-1234-123456789012" \
  --client-secret "your-secret-here" \
  --tenant-id "87654321-4321-4321-4321-210987654321" \
  --subscription-id "11111111-2222-3333-4444-555555555555" \
  --resource-group "ha-k3s-rg" \
  --cluster-name "ha-k3s-cluster" \
  --location "eastus" \
  --node-role server \
  --verbose
```

**Important**: Only the first server node connects to Azure Arc. Additional nodes join the existing cluster.

### Step 2: Obtain Join Information

After the first server is deployed, the script automatically displays the join token information in the "CLUSTER EXPANSION" section. You can also get this information later:

```bash
# View join token in status
./setup-k3s-arc.sh --status --node-role server

# Or get the token manually if needed
sudo cat /var/lib/rancher/k3s/server/node-token

# Get the server IP address
ip addr show | grep "inet " | grep -v 127.0.0.1
```

Example output from deployment:
```
🎯 CLUSTER EXPANSION
     Join additional server nodes with:
     ./setup-k3s-arc.sh --node-role server --server-ip 10.0.1.10 --join-token K107c4bb8c6b3d4a1234567890abcdef::server:1234567890abcdef

     Join worker nodes with:
     ./setup-k3s-arc.sh --node-role agent --server-ip 10.0.1.10 --join-token K107c4bb8c6b3d4a1234567890abcdef::server:1234567890abcdef
```

### Step 3: Deploy Additional Server Nodes

For **high availability**, deploy at least 2 more server nodes:

**Server Node 2:**
```bash
./setup-k3s-arc.sh \
  --node-role server \
  --server-ip 10.0.1.10 \
  --join-token "K107c4bb8c6b3d4a1234567890abcdef::server:1234567890abcdef" \
  --verbose
```

**Server Node 3:**
```bash
./setup-k3s-arc.sh \
  --node-role server \
  --server-ip 10.0.1.10 \
  --join-token "K107c4bb8c6b3d4a1234567890abcdef::server:1234567890abcdef" \
  --verbose
```

### Step 4: Deploy Agent Nodes (Optional)

Agent nodes run workloads but don't participate in cluster management:

```bash
./setup-k3s-arc.sh \
  --node-role agent \
  --server-ip 10.0.1.10 \
  --join-token "K107c4bb8c6b3d4a1234567890abcdef::server:1234567890abcdef" \
  --verbose
```

### Step 5: Verify Cluster Health

From any server node:

```bash
# Check all nodes
kubectl get nodes -o wide

# Verify etcd cluster health
sudo k3s etcd-snapshot save --etcd-s3=false check

# Check system pods
kubectl get pods -n kube-system

# Verify Arc connection
kubectl get pods -n azure-arc
```

Expected output:
```
NAME       STATUS   ROLES                       AGE   VERSION
server1    Ready    control-plane,master,etcd   10m   v1.28.4+k3s1
server2    Ready    control-plane,master,etcd   8m    v1.28.4+k3s1
server3    Ready    control-plane,master,etcd   6m    v1.28.4+k3s1
agent1     Ready    <none>                      4m    v1.28.4+k3s1
agent2     Ready    <none>                      2m    v1.28.4+k3s1
```

## Load Balancer Configuration

### External Load Balancer (Recommended)

For production HA clusters, use an external load balancer in front of server nodes:

#### HAProxy Configuration Example

```haproxy
# /etc/haproxy/haproxy.cfg
global
    daemon

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend k3s_frontend
    bind *:6443
    mode tcp
    default_backend k3s_servers

backend k3s_servers
    mode tcp
    balance roundrobin
    server server1 10.0.1.10:6443 check
    server server2 10.0.1.11:6443 check
    server server3 10.0.1.12:6443 check
```

#### NGINX Load Balancer Example

```nginx
# /etc/nginx/nginx.conf
stream {
    upstream k3s_servers {
        server 10.0.1.10:6443;
        server 10.0.1.11:6443;
        server 10.0.1.12:6443;
    }

    server {
        listen 6443;
        proxy_pass k3s_servers;
        proxy_timeout 10s;
        proxy_responses 1;
    }
}
```

### Using Load Balancer with Additional Nodes

When using a load balancer, point new nodes to the load balancer IP:

```bash
./setup-k3s-arc.sh \
  --node-role server \
  --server-ip 10.0.1.100 \  # Load balancer IP
  --join-token "K107c4bb8c6b3d4a1234567890abcdef::server:1234567890abcdef"
```

## Network Requirements

### Required Ports

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 6443 | TCP | Inbound | Kubernetes API server |
| 10250 | TCP | Inbound | Kubelet API |
| 8472 | UDP | Bidirectional | Flannel VXLAN |
| 51820 | UDP | Bidirectional | Flannel Wireguard (if enabled) |
| 51821 | UDP | Bidirectional | Flannel Wireguard IPv6 (if enabled) |
| 2379-2380 | TCP | Server-to-Server | etcd client/peer communication |

### Firewall Configuration

```bash
# On all nodes
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=8472/udp
sudo firewall-cmd --permanent --add-port=51820/udp
sudo firewall-cmd --permanent --add-port=51821/udp

# On server nodes only
sudo firewall-cmd --permanent --add-port=2379/tcp
sudo firewall-cmd --permanent --add-port=2380/tcp

sudo firewall-cmd --reload
```

## Production Considerations

### Node Placement

#### Anti-Affinity Recommendations
- Place server nodes in different availability zones
- Use different physical hosts for server nodes
- Distribute agent nodes across zones for workload resilience

#### Example Azure Deployment
```bash
# Zone 1
./setup-k3s-arc.sh --location eastus --cluster-name prod-cluster-z1 [other-options]

# Zone 2  
./setup-k3s-arc.sh --node-role server --server-ip ZONE1_LB_IP [other-options]

# Zone 3
./setup-k3s-arc.sh --node-role server --server-ip ZONE1_LB_IP [other-options]
```

### Resource Planning

#### Server Node Sizing
- **Development**: 2 CPU, 4GB RAM, 20GB disk
- **Production**: 4 CPU, 8GB RAM, 100GB SSD
- **Large Production**: 8 CPU, 16GB RAM, 200GB SSD

#### Agent Node Sizing
- Depends on workload requirements
- Consider resource limits and requests for pods
- Plan for system overhead (kubelet, kube-proxy, CNI)

### Backup Strategy

#### Automated etcd Snapshots
```bash
# Configure automatic snapshots (on server nodes)
sudo systemctl edit k3s

# Add:
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s server --etcd-snapshot-schedule-cron "0 */6 * * *" --etcd-snapshot-retention 10
```

#### Manual Backup
```bash
# Create snapshot
sudo k3s etcd-snapshot save backup-$(date +%Y%m%d-%H%M%S)

# List snapshots
sudo k3s etcd-snapshot ls

# Restore from snapshot (cluster must be stopped)
sudo k3s etcd-snapshot restore backup-20250118-120000
```

## Scaling Operations

### Adding Nodes

#### Adding Server Nodes
```bash
# Get current join token from existing server status
./setup-k3s-arc.sh --status --node-role server

# Or get the token manually if needed
sudo cat /var/lib/rancher/k3s/server/node-token

# Deploy new server
./setup-k3s-arc.sh \
  --node-role server \
  --server-ip EXISTING_SERVER_IP \
  --join-token "CURRENT_TOKEN"
```

#### Adding Agent Nodes
```bash
./setup-k3s-arc.sh \
  --node-role agent \
  --server-ip EXISTING_SERVER_IP \
  --join-token "CURRENT_TOKEN"
```

### Removing Nodes

#### Drain Node
```bash
# Safely remove workloads
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data

# Remove from cluster
kubectl delete node NODE_NAME
```

#### Remove Server Node (Careful!)
```bash
# Check etcd member list
kubectl exec -n kube-system etcd-SERVER_NAME -- etcdctl member list

# Remove etcd member
kubectl exec -n kube-system etcd-SERVER_NAME -- etcdctl member remove MEMBER_ID

# Drain and delete node
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data
kubectl delete node NODE_NAME
```

## Troubleshooting Multi-Node Issues

### Common Problems

#### Nodes Can't Join Cluster
```bash
# Check network connectivity
telnet SERVER_IP 6443

# Verify join token
echo "TOKEN_HERE" | base64 -d

# Check firewall rules
sudo firewall-cmd --list-ports
```

#### etcd Cluster Issues
```bash
# Check etcd health
sudo k3s etcd-snapshot save --etcd-s3=false health-check

# View etcd logs
journalctl -u k3s -f | grep etcd

# Check etcd member status
kubectl exec -n kube-system etcd-SERVER_NAME -- etcdctl endpoint health
```

#### Split-Brain Recovery
```bash
# Stop K3s on all nodes
sudo systemctl stop k3s

# On the node with the most recent data, restore from snapshot
sudo k3s etcd-snapshot restore LATEST_SNAPSHOT

# Start K3s on restored node
sudo systemctl start k3s

# Remove other server nodes from cluster and re-add them
```

### Monitoring Cluster Health

#### Essential Checks
```bash
# Node status
kubectl get nodes

# System pods
kubectl get pods -n kube-system

# Arc agents
kubectl get pods -n azure-arc

# etcd health
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl endpoint health

# Cluster info
kubectl cluster-info
```

#### Automated Health Monitoring
```bash
#!/bin/bash
# health-check.sh

echo "=== Node Status ==="
kubectl get nodes

echo -e "\n=== System Pods ==="
kubectl get pods -n kube-system | grep -E "(coredns|metrics-server|local-path)"

echo -e "\n=== Arc Status ==="
kubectl get pods -n azure-arc

echo -e "\n=== etcd Health ==="
kubectl exec -n kube-system etcd-$(hostname) -- etcdctl endpoint health 2>/dev/null || echo "etcd check failed"
```

## Advanced Configurations

### Custom Cluster Configuration

#### Large Clusters (>50 nodes)
For large clusters, use standard deployment but consider:
- Multiple server nodes for HA
- Adequate DNS configuration
- Resource planning for node scaling

```bash
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group "large-cluster-rg" \
  --cluster-name "large-cluster" \
  --node-role server \
  --dns-servers "1.1.1.1,1.0.0.1"
```

#### Edge Computing Setup
```bash
# Minimal server nodes
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group "edge-rg" \
  --cluster-name "edge-cluster" \
  --node-role server

# Lightweight agent nodes
./setup-k3s-arc.sh \
  --node-role agent \
  --server-ip SERVER_IP \
  --join-token TOKEN
```

### Integration Considerations

#### External Database Support
K3s can use external databases instead of embedded etcd for very large deployments. However, this setup requires manual K3s configuration outside of this deployment tool. For most use cases, the embedded etcd HA setup is recommended.

---

*For basic deployment, see [Quick Start Guide](./quickstart.md). For troubleshooting cluster issues, see [Troubleshooting Guide](./troubleshooting.md). For production recommendations, see [Enterprise Guide](./enterprise.md).*