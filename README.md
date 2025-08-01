# K3s + Azure Arc Automated Setup

Automated deployment scripts for K3s clusters with Azure Arc integration, featuring comprehensive offline installation capabilities.

## Overview

This project provides enterprise-ready automation for deploying K3s Kubernetes clusters with Azure Arc connectivity. The scripts handle everything from system preparation to Arc agent deployment, with full offline support for air-gapped environments.

## Features

✅ **Comprehensive Offline Support** - Complete offline installation capability  
✅ **System Preparation** - Automated system updates and dependency installation  
✅ **K3s Installation** - Full K3s cluster setup with DNS optimization  
✅ **Azure Arc Integration** - Automated Arc agent deployment and connectivity  
✅ **Multi-Architecture** - Support for amd64, arm64, and arm architectures  
✅ **Enterprise Ready** - Secure authentication, logging, and error handling  
✅ **Upgrade Support** - In-place upgrades for K3s and components  

## Quick Start

### Online Installation (Standard)
```bash
# Deploy K3s + Azure Arc with internet connectivity
./setup-k3s-arc.sh --client-id YOUR_CLIENT_ID \
                   --tenant-id YOUR_TENANT_ID \
                   --subscription-id YOUR_SUBSCRIPTION_ID \
                   --resource-group YOUR_RESOURCE_GROUP \
                   --cluster-name YOUR_CLUSTER_NAME \
                   --location YOUR_LOCATION
```

### Offline Installation (Air-Gapped)
```bash
# 1. Build offline bundle (requires internet)
./build-k3s-arc-offline-install-bundle.sh

# 2. Transfer bundle to target system and install
./install-k3s-arc-offline-install-bundle.sh k3s-arc-offline-install-bundle-YYYYMMDD.tar.gz

# 3. Deploy without internet connectivity
./setup-k3s-arc.sh --offline \
                   --client-id YOUR_CLIENT_ID \
                   --tenant-id YOUR_TENANT_ID \
                   --subscription-id YOUR_SUBSCRIPTION_ID \
                   --resource-group YOUR_RESOURCE_GROUP \
                   --cluster-name YOUR_CLUSTER_NAME \
                   --location YOUR_LOCATION
```

## Offline Installation Guide

### Why Choose Offline Installation?

- **Air-Gapped Environments**: Complete deployment without internet access
- **Bandwidth Optimization**: Reduce download requirements by ~300MB+ per installation
- **Consistency**: Predictable component versions across deployments
- **Security**: Minimize external dependencies and attack surface

### Comprehensive Offline Process

The offline installation handles **complete system preparation**:

#### Phase 1: Bundle Creation
```bash
./build-k3s-arc-offline-install-bundle.sh [--verbose]
```

**What gets bundled:**
- Helm binaries (multi-architecture)
- kubectl binaries (multi-architecture)
- Azure CLI Python wheels and dependencies
- K3s installation script from get.k3s.io
- Installation scripts and manifests
- SHA256 checksums for integrity validation

#### Phase 2: Offline Installation
```bash
./install-k3s-arc-offline-install-bundle.sh [--upgrade] BUNDLE_FILE
```

**What gets installed:**
1. **System Updates**: `dnf update -y` (with yum fallback)
2. **Dependencies**: curl, wget, git, firewalld, jq, tar
3. **K3s Installation**: Complete cluster setup using bundled installer
4. **Helm**: Multi-architecture binary installation
5. **kubectl**: Multi-architecture binary installation  
6. **Azure CLI**: Local pip wheel installation
7. **Completion Markers**: Component detection for setup script

#### Phase 3: Arc Deployment
```bash
./setup-k3s-arc.sh --offline [arc-options]
```

**Smart offline behavior:**
- Automatically detects offline components
- Bypasses system updates and dependency installation
- Skips K3s installation (uses existing cluster)
- Uses pre-installed Helm, kubectl, and Azure CLI
- Optimized progress display (8 steps vs 14 online)

### Installation Locations

**System Binaries:**
- Helm: `/usr/local/bin/helm` → `/usr/bin/helm` (symlink)
- kubectl: `/usr/local/bin/kubectl` → `/usr/bin/kubectl` (symlink)

**User Components:**
- Azure CLI: `~/.local/bin/az` (in PATH via ~/.bashrc)
- Azure CLI Wheels: `~/.k3s-arc-offline/azure-cli/wheels/`
- Completion Marker: `~/.k3s-arc-offline/components-installed`

**System Services:**
- K3s: systemd service (`k3s.service`)
- Firewall: firewalld configuration

## Command Reference

### setup-k3s-arc.sh Options

**Required Parameters:**
```
--client-id CLIENT_ID              Azure AD application client ID
--tenant-id TENANT_ID              Azure AD tenant ID  
--subscription-id SUBSCRIPTION_ID   Azure subscription ID
--resource-group RESOURCE_GROUP     Azure resource group name
--cluster-name CLUSTER_NAME         K3s cluster name for Arc registration
--location LOCATION                 Azure region (e.g., eastus, westus2)
```

**Offline Options:**
```
--offline                          Use pre-installed offline components
--no-ntp                          Skip time synchronization
```

**System Options:**
```
--no-updates                      Skip system package updates
--no-firewall                     Skip firewall configuration
--verbose                         Show detailed technical output
--quiet                           Minimal output (errors only)
```

**Utility Options:**
```
--status                          Show current installation status
--help                            Show comprehensive help
```

### Bundle Management

**Create Bundle:**
```bash
./build-k3s-arc-offline-install-bundle.sh [--verbose] [--quiet]
```

**Install Bundle:**
```bash
./install-k3s-arc-offline-install-bundle.sh [--upgrade] [--verbose] BUNDLE_FILE
```

**Remove Bundle:**
```bash
./build-k3s-arc-offline-install-bundle.sh --remove-bundle BUNDLE_FILE
```

## Verification and Status

### Check Installation Status
```bash
# Overall status
./setup-k3s-arc.sh --status

# Component verification  
helm version
kubectl version --client
az version
systemctl status k3s
```

### Verify Offline Detection
```bash
# Check completion marker
cat ~/.k3s-arc-offline/components-installed

# Test offline mode detection
./setup-k3s-arc.sh --offline --help
```

### Verify K3s Cluster
```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check Arc agents (after deployment)
kubectl get pods -n azure-arc
```

## Architecture Support

**Supported Architectures:**
- x86_64 (amd64) - Intel/AMD 64-bit
- aarch64 (arm64) - ARM 64-bit (Apple M1/M2, ARM servers)
- armv7l (arm) - ARM 32-bit (Raspberry Pi, etc.)

**Supported Operating Systems:**
- Rocky Linux 8/9
- RHEL 8/9  
- CentOS Stream 8/9
- Other RHEL derivatives with dnf/yum

## Troubleshooting

### Common Issues

**Offline Components Not Detected:**
```bash
# Check completion marker exists
ls -la ~/.k3s-arc-offline/components-installed

# Verify component installation
command -v helm && command -v kubectl && command -v az
```

**K3s Service Issues:**
```bash
# Check K3s status
systemctl status k3s
journalctl -u k3s --since "10 minutes ago"

# Check kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

**Arc Connection Issues:**
```bash
# Check Arc agents
kubectl get pods -n azure-arc
kubectl logs -n azure-arc -l app.kubernetes.io/component=connect-agent
```

### Getting Help

1. **Verbose Mode**: Run with `--verbose` for detailed output
2. **Check Logs**: Use `journalctl -u k3s` for K3s issues
3. **Status Check**: Run `./setup-k3s-arc.sh --status` for overview
4. **Component Verification**: Test individual components (helm, kubectl, az)

## Security Considerations

- **Single Sudo Prompt**: Secure password handling with memory-only storage
- **Checksum Validation**: SHA256 verification for all bundle components
- **Minimal Privileges**: Components installed with appropriate permissions
- **Clean Credentials**: Automatic cleanup of sensitive information

## Contributing

When contributing to this project:

1. Follow existing bash scripting patterns and glyph usage
2. Test both online and offline installation modes
3. Verify multi-architecture compatibility
4. Update documentation for new features
5. Ensure security best practices are maintained

## License

This project is licensed under the terms specified by C Spire.

---

**Need Help?** Check the comprehensive help: `./setup-k3s-arc.sh --help`  
**Documentation:** See `docs/` directory for additional guides  
**Implementation:** Review `OFFLINE_IMPLEMENTATION_PLAN.md` for technical details