# K3s + Azure Arc Deployment Tool

This project provides enterprise-grade automation for deploying Kubernetes (K3s) clusters with Azure Arc integration. The tool is designed for production environments and includes comprehensive error handling, DNS troubleshooting, and support for both single-node and multi-node cluster deployments.

## 🚀 Quick Start

```bash
# Single-node cluster with Azure Arc
./setup-k3s-arc.sh \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group my-rg \
  --cluster-name my-cluster

# Check deployment status
./setup-k3s-arc.sh --status

# Run diagnostics
./setup-k3s-arc.sh --diagnostics
```

## 📚 Documentation Structure

### Getting Started
- [Installation Guide](./installation.md) - System requirements and setup
- [Quick Start Guide](./quickstart.md) - Get up and running quickly
- [Configuration Options](./configuration.md) - All available parameters and options

### Deployment Scenarios
- [Single Node Deployment](./single-node.md) - Simple single-node cluster
- [Multi-Node Clusters](./multi-node.md) - High-availability and worker nodes
- [Enterprise Deployment](./enterprise.md) - Production considerations

### Operations
- [Troubleshooting Guide](./troubleshooting.md) - Common issues and solutions
- [DNS Troubleshooting](./dns-troubleshooting.md) - DNS-specific issues and fixes
- [Diagnostics](./diagnostics.md) - Built-in diagnostic tools
- [Maintenance](./maintenance.md) - Ongoing cluster maintenance

### Reference
- [Architecture](./architecture.md) - System design and components
- [Command Reference](./command-reference.md) - Complete CLI documentation
- [Environment Notes](./environment-notes.md) - Platform-specific considerations
- [FAQ](./faq.md) - Frequently asked questions

## 🏗️ Key Features

- **Idempotent Operations**: Safe to run multiple times
- **Enterprise DNS Handling**: Automatic DNS fixes for VM environments
- **Multi-Architecture Support**: x86_64, ARM64, and ARM32
- **Comprehensive Diagnostics**: Built-in troubleshooting tools
- **GitOps Ready**: Flux extension automatically installed
- **Production Tested**: Validated on RHEL 9, Rocky Linux, and CentOS

## 🔧 DNS Troubleshooting

This tool includes sophisticated DNS troubleshooting capabilities, particularly important for VM environments where DNS forwarding can cause Arc agent certificate issues.

**Automatic DNS Fixes**: The tool automatically detects and fixes DNS issues that prevent Azure Arc agents from generating certificates.

**Supported DNS Servers**:
- Google DNS: `8.8.8.8, 8.8.4.4` (default)
- Cloudflare DNS: `1.1.1.1, 1.0.0.1` (recommended for VM environments)
- Custom/Corporate DNS servers

See [DNS Troubleshooting Guide](./dns-troubleshooting.md) for detailed information.

## 🛠️ Environment Support

### Tested Platforms
- **RHEL 9**: Production validated
- **Rocky Linux 9/10**: Full support
- **CentOS Stream**: Compatible

### VM Environments
- **VMware**: Extensively tested (DNS fixes optimize for VMware networking)
- **Azure VMs**: Good compatibility
- **AWS EC2**: Supported with considerations
- **Google Cloud**: Supported

### Architectures
- **x86_64**: Full support (recommended)
- **ARM64/aarch64**: Supported with some limitations
- **ARM32**: Limited support

## 📊 Monitoring and Status

The tool provides comprehensive status tracking:

```bash
# Quick status check
./setup-k3s-arc.sh --status

# Detailed system diagnostics
./setup-k3s-arc.sh --diagnostics

# Service principal validation
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP
```

## 🔒 Security Considerations

- Uses Azure service principals for authentication
- Supports resource-group-scoped permissions
- Secure credential handling
- No credentials stored in logs or state files

## 📈 Production Deployment

For production deployments, see the [Enterprise Deployment Guide](./enterprise.md) which covers:
- High-availability cluster setup
- DNS configuration best practices
- Security considerations
- Monitoring and maintenance

## 🆘 Getting Help

1. **Check Status**: `./setup-k3s-arc.sh --status`
2. **Run Diagnostics**: `./setup-k3s-arc.sh --diagnostics`
3. **Review Troubleshooting**: See [troubleshooting.md](./troubleshooting.md)
4. **Check DNS Issues**: See [dns-troubleshooting.md](./dns-troubleshooting.md)

## 📄 License

Production deployment tool for K3s + Azure Arc integration.

## 🔄 Version Information

- Script Version: 2025.07.17
- K3s: Latest stable
- Azure Arc: Latest agents
- Flux: Microsoft Flux extension

---

*This documentation covers the comprehensive K3s + Azure Arc deployment automation tool with enterprise-grade DNS troubleshooting and multi-environment support.*