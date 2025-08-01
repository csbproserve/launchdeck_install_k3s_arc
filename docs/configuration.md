# Configuration Reference

This guide covers all command-line options and parameters for the K3s + Azure Arc deployment tool.

## Command Structure

```bash
./setup-k3s-arc.sh [OPTIONS]
```

## Required Parameters (for new clusters)

### Azure Service Principal
```bash
--client-id CLIENT_ID         # Azure service principal application ID
--client-secret CLIENT_SECRET # Azure service principal secret
--tenant-id TENANT_ID         # Azure Active Directory tenant ID
--subscription-id SUB_ID      # Azure subscription ID
--resource-group RG_NAME      # Azure resource group name
--cluster-name CLUSTER_NAME   # Name for the Arc-connected cluster
```

## Optional Parameters

### Azure Configuration
```bash
--location LOCATION           # Azure region (default: eastus)
```

### Multi-Node Configuration
```bash
--node-role ROLE              # K3s node role: server or agent
--server-ip IP_ADDRESS        # For joining nodes: IP of the K3s server
--join-token TOKEN            # For joining nodes: K3s join token
```

### DNS Configuration
```bash
--dns-servers DNS_LIST        # Comma-separated DNS servers (default: 8.8.8.8,8.8.4.4)
--no-fix-dns                  # Skip automatic DNS fixes
```

### Operation Modes
```bash
--status                     # Show current installation status
--diagnostics                # Run comprehensive diagnostics
--diagnose-service-principal # Validate service principal only
--verbose                    # Enable detailed output
--quiet                      # Suppress non-error output
--help                       # Show help message
```

## Configuration Examples

### Basic Single-Node Deployment
```bash
./setup-k3s-arc.sh \
  --client-id "12345678-1234-1234-1234-123456789012" \
  --client-secret "your-secret-here" \
  --tenant-id "87654321-4321-4321-4321-210987654321" \
  --subscription-id "11111111-2222-3333-4444-555555555555" \
  --resource-group "my-k3s-rg" \
  --cluster-name "my-k3s-cluster" \
  --location "eastus"
```

### High-Availability Cluster

**Server Node 1:**
```bash
./setup-k3s-arc.sh \
  --client-id "12345678-1234-1234-1234-123456789012" \
  --client-secret "your-secret-here" \
  --tenant-id "87654321-4321-4321-4321-210987654321" \
  --subscription-id "11111111-2222-3333-4444-555555555555" \
  --resource-group "my-k3s-rg" \
  --cluster-name "my-k3s-cluster" \
  --location "eastus" \
  --node-role server
```

**Additional Server Nodes:**
```bash
./setup-k3s-arc.sh \
  --node-role server \
  --server-ip 10.0.1.10 \
  --join-token "K107c4bb8c6b3d4..."
```

**Agent Nodes:**
```bash
./setup-k3s-arc.sh \
  --node-role agent \
  --server-ip 10.0.1.10 \
  --join-token "K107c4bb8c6b3d4..."
```

### VM Environment with DNS Optimization
```bash
./setup-k3s-arc.sh \
  --client-id "12345678-1234-1234-1234-123456789012" \
  --client-secret "your-secret-here" \
  --tenant-id "87654321-4321-4321-4321-210987654321" \
  --subscription-id "11111111-2222-3333-4444-555555555555" \
  --resource-group "my-k3s-rg" \
  --cluster-name "my-vm-cluster" \
  --location "eastus" \
  --dns-servers "1.1.1.1,1.0.0.1" \
  --verbose
```

### Corporate Environment with Custom DNS
```bash
./setup-k3s-arc.sh \
  --client-id "12345678-1234-1234-1234-123456789012" \
  --client-secret "your-secret-here" \
  --tenant-id "87654321-4321-4321-4321-210987654321" \
  --subscription-id "11111111-2222-3333-4444-555555555555" \
  --resource-group "corp-k3s-rg" \
  --cluster-name "corp-cluster" \
  --location "eastus" \
  --dns-servers "10.0.0.53,10.0.0.54"
```

### Disable Automatic DNS Fixes
```bash
./setup-k3s-arc.sh \
  --client-id "12345678-1234-1234-1234-123456789012" \
  --client-secret "your-secret-here" \
  --tenant-id "87654321-4321-4321-4321-210987654321" \
  --subscription-id "11111111-2222-3333-4444-555555555555" \
  --resource-group "my-k3s-rg" \
  --cluster-name "my-cluster" \
  --no-fix-dns
```

## State File Management

### State File: ~/.k3s-arc-setup-state

The script tracks deployment progress in a state file to enable idempotent operations.

**State File Operations:**
```bash
# Check current status
./setup-k3s-arc.sh --status

# Reset state (force re-run all steps)
rm ~/.k3s-arc-setup-state

# Check what steps need to be completed
./setup-k3s-arc.sh --status
```

**State File Format:**
```
step_name=completed
time_sync_configured=completed
system_update=completed
k3s_installed=completed
arc_connected=completed
```

## DNS Configuration

### Default DNS Behavior
- Default DNS servers: `8.8.8.8,8.8.4.4` (Google DNS)
- Automatic DNS fixes enabled by default for Arc agent compatibility
- DNS fixes target VM environments where DNS forwarding often fails

### Custom DNS Servers
```bash
# Use Cloudflare DNS (recommended for VM environments)
--dns-servers "1.1.1.1,1.0.0.1"

# Use corporate DNS servers
--dns-servers "10.0.0.53,10.0.0.54"

# Use quad9 DNS
--dns-servers "9.9.9.9,149.112.112.112"
```

### Disable DNS Fixes
```bash
# Skip automatic DNS configuration changes
--no-fix-dns
```

## Diagnostic Commands

### System Diagnostics
```bash
# Comprehensive system health check
./setup-k3s-arc.sh --diagnostics
```

### Service Principal Validation
```bash
./setup-k3s-arc.sh --diagnose-service-principal \
  --client-id $CLIENT_ID \
  --client-secret $CLIENT_SECRET \
  --tenant-id $TENANT_ID \
  --subscription-id $SUB_ID \
  --resource-group $RESOURCE_GROUP
```

### Installation Status
```bash
# Check current deployment status
./setup-k3s-arc.sh --status
```

## Default Values

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `--location` | `eastus` | Azure region |
| `--dns-servers` | `8.8.8.8,8.8.4.4` | DNS servers for CoreDNS |
| DNS fixes | Enabled | Automatic DNS configuration for Arc compatibility |

## Common Patterns

### Development Environment
```bash
./setup-k3s-arc.sh \
  --client-id "$CLIENT_ID" \
  --client-secret "$CLIENT_SECRET" \
  --tenant-id "$TENANT_ID" \
  --subscription-id "$SUB_ID" \
  --resource-group "dev-k3s-rg" \
  --cluster-name "dev-cluster" \
  --verbose
```

### Production Environment
```bash
./setup-k3s-arc.sh \
  --client-id "$CLIENT_ID" \
  --client-secret "$CLIENT_SECRET" \
  --tenant-id "$TENANT_ID" \
  --subscription-id "$SUB_ID" \
  --resource-group "prod-k3s-rg" \
  --cluster-name "prod-cluster" \
  --location "eastus" \
  --quiet
```

---

*For installation requirements, see [Installation Guide](./installation.md). For troubleshooting configuration issues, see [Troubleshooting Guide](./troubleshooting.md).*