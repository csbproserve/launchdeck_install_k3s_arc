# Installation Guide

This guide covers system requirements, prerequisites, and initial setup for the K3s + Azure Arc deployment tool.

## System Requirements

### Minimum Hardware
- **CPU**: 2+ cores (4+ recommended for production)
- **Memory**: 2GB RAM (4GB+ recommended)
- **Storage**: 20GB available space (SSD recommended)
- **Network**: Internet connectivity required

### Operating System Support

#### Fully Supported
- **RHEL 9**: Production validated
- **Rocky Linux 9/10**: Full support
- **CentOS Stream**: Compatible

#### Architecture Support
- **x86_64**: Full support (recommended)
- **ARM64/aarch64**: Supported with limitations
- **ARM32**: Limited support

### Network Requirements

#### Required Outbound Connectivity
- **Kubernetes Components**:
  - `get.k3s.io` (K3s installation)
  - `github.com` (Helm installation)
  - Container registries for K3s images

- **Azure Services**:
  - `login.microsoftonline.com` (Azure authentication)
  - `management.azure.com` (Azure Resource Manager)
  - `*.servicebus.windows.net` (Arc agents)

- **DNS Servers** (for VM environments):
  - Google DNS: `8.8.8.8`, `8.8.4.4`
  - Cloudflare DNS: `1.1.1.1`, `1.0.0.1`

#### Firewall Ports
The tool automatically configures these ports:
- **6443/tcp**: Kubernetes API server
- **10250/tcp**: Kubelet API
- **8472/udp**: Flannel VXLAN
- **51820/udp**: Flannel Wireguard
- **51821/udp**: Flannel Wireguard (IPv6)

## Azure Prerequisites

### Azure Service Principal

You'll need an Azure service principal with appropriate permissions:

#### Required Information
- **Client ID**: Service principal application ID
- **Client Secret**: Service principal password/secret
- **Tenant ID**: Azure AD tenant ID
- **Subscription ID**: Target Azure subscription
- **Resource Group**: Target resource group name

#### Required Permissions
The service principal needs the **"Kubernetes Cluster - Azure Arc Onboarding"** role on the target resource group.

#### Creating a Service Principal

```bash
# Create service principal
az ad sp create-for-rbac --name "k3s-arc-sp" --role "Kubernetes Cluster - Azure Arc Onboarding" --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# Output will include:
# - appId (client-id)
# - password (client-secret)
# - tenant (tenant-id)
```

#### Verify Service Principal

```bash
# Test service principal configuration
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP
```

## Installation Process

### 1. Download the Tool

```bash
# Clone or download the deployment tool
# Ensure setup-k3s-arc.sh is executable
chmod +x setup-k3s-arc.sh
```

### 2. Verify System Compatibility

```bash
# Check system architecture and compatibility
./setup-k3s-arc.sh --diagnostics
```

### 3. Validate Prerequisites

```bash
# Verify Azure service principal
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP
```

## VM Environment Considerations

### VMware Environments

VMware VMs often experience DNS issues that affect Azure Arc agent certificate generation:

- **Default DNS**: VM DNS forwarding may not work reliably
- **Recommended DNS**: Use Cloudflare DNS (`1.1.1.1, 1.0.0.1`)
- **Time Sync**: Ensure VMware Tools time synchronization is enabled

```bash
# Deploy with Cloudflare DNS (recommended for VMware)
./setup-k3s-arc.sh \
  --dns-servers 1.1.1.1,1.0.0.1 \
  # ... other parameters
```

### Cloud Environments

#### Azure VMs
- Generally good compatibility
- Azure metadata service works well with Arc
- Standard network security group rules apply

#### AWS EC2
- Instance metadata service considerations
- Security groups must allow K3s ports
- Time synchronization usually reliable

#### Google Cloud Platform
- Similar considerations to AWS
- VPC firewall rules important
- Time synchronization reliable

## Time Synchronization

Critical for Azure authentication and package verification:

### RHEL/Rocky Linux
```bash
# Enable time synchronization
sudo timedatectl set-ntp true
sudo systemctl enable systemd-timesyncd

# Verify synchronization
timedatectl status
```

### Alternative: Chronyd
```bash
# If chronyd is preferred
sudo systemctl enable chronyd
sudo systemctl start chronyd

# Verify synchronization
chronyc sources -v
```

## Post-Installation Verification

### 1. System Status
```bash
# Check overall setup status
./setup-k3s-arc.sh --status
```

### 2. Service Verification
```bash
# Verify K3s service
systemctl status k3s

# Check cluster access
kubectl get nodes

# Verify Arc connection (if applicable)
az connectedk8s show --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP
```

### 3. DNS Health Check
```bash
# Test external DNS
nslookup google.com

# Test Azure services
nslookup login.microsoftonline.com

# Test cluster internal DNS
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i -- nslookup kubernetes.default.svc.cluster.local
```

## Troubleshooting Installation Issues

### Common Issues

#### Time Synchronization Errors
```bash
# Force time synchronization
sudo chronyc makestep
sudo systemctl restart chronyd
```

#### DNS Resolution Problems
```bash
# Apply DNS fix manually
./setup-k3s-arc.sh --dns-servers 1.1.1.1,1.0.0.1
```

#### Service Principal Issues
```bash
# Verify service principal permissions
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP
```

#### Architecture Compatibility
```bash
# Check system architecture
uname -m

# Verify tool compatibility
./setup-k3s-arc.sh --diagnostics
```

## Security Considerations

### Credential Handling
- Service principal credentials are not stored persistently
- Use environment variables or secure credential storage
- Avoid hardcoding credentials in scripts

### Network Security
- Firewall rules are automatically configured
- Additional corporate firewall rules may be needed
- Consider network segmentation for production

### Access Control
- Use resource-group-scoped service principals when possible
- Follow principle of least privilege
- Regular credential rotation recommended

## Next Steps

After successful installation:

1. **Verify Status**: Run `./setup-k3s-arc.sh --status`
2. **Check Diagnostics**: Run `./setup-k3s-arc.sh --diagnostics`
3. **Deploy Applications**: Use kubectl or GitOps with Flux
4. **Add Nodes**: Follow [multi-node guide](./multi-node.md) if needed

---

*For deployment-specific guides, see [Quick Start](./quickstart.md) or [Enterprise Deployment](./enterprise.md).*