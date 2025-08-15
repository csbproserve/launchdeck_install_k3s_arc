# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a K3s + Azure Arc automated deployment system with comprehensive offline installation capabilities. The project provides enterprise-ready automation for deploying Kubernetes clusters with Azure Arc connectivity, featuring robust DNS troubleshooting and multi-architecture support.

## Key Scripts and Commands

### Main Deployment Scripts
- `./setup-k3s-arc.sh` - Main deployment script for K3s + Azure Arc integration
- `./build-k3s-arc-offline-install-bundle.sh` - Creates offline installation bundles
- `./install-k3s-arc-offline-install-bundle.sh` - Installs from offline bundles
- `./uninstall-k3s-arc.sh` - Removes K3s and Arc components

### Common Commands
```bash
# Standard online deployment
./setup-k3s-arc.sh --client-id ID --tenant-id TENANT --subscription-id SUB --resource-group RG --cluster-name NAME --location LOCATION

# Offline deployment workflow
./build-k3s-arc-offline-install-bundle.sh
./install-k3s-arc-offline-install-bundle.sh bundle.tar.gz
./setup-k3s-arc.sh --offline [other-params]

# Status and diagnostics
./setup-k3s-arc.sh --status
./setup-k3s-arc.sh --diagnostics

# Uninstall
./uninstall-k3s-arc.sh
```

## Architecture

### Dual-Mode Operation
The system operates in two distinct modes:
1. **Online Mode**: Downloads dependencies during installation
2. **Offline Mode**: Uses pre-bundled components for air-gapped environments

### Component Structure
- **System Layer**: OS updates, firewall, dependencies (curl, wget, git, jq)
- **Kubernetes Layer**: K3s installation and configuration
- **Tools Layer**: Helm, kubectl, Azure CLI installation
- **Arc Layer**: Azure Arc agent deployment and cluster registration

### Offline Bundle System
- Multi-architecture binary support (amd64, arm64, arm)
- SHA256 checksum validation for integrity
- Git LFS for large bundle storage (~130MB+)
- Component detection system using completion markers

## Code Patterns and Conventions

### Script Structure
All scripts follow consistent patterns:
- Bash with `set -e` for strict error handling
- Color-coded output using ANSI escape codes
- Unicode glyphs for status indicators (✅, ❌, ⚠️, etc.)
- Comprehensive help text with `--help` flag

### Security Patterns
- Memory-only sudo password storage
- Automatic credential cleanup
- No sensitive data in logs or state files
- Resource-group-scoped service principal permissions

### Error Handling
- Idempotent operations (safe to run multiple times)
- Comprehensive DNS troubleshooting for VM environments
- Automatic fallback for package managers (dnf → yum)
- Progress tracking with step counters

## Key Implementation Details

### DNS Resolution System
The project includes sophisticated DNS troubleshooting specifically for VM environments where DNS forwarding causes Azure Arc certificate issues. The system can automatically detect and fix DNS problems using Google DNS (8.8.8.8) or Cloudflare DNS (1.1.1.1).

### Multi-Architecture Support
All binary components are automatically detected and installed based on system architecture:
- x86_64 (amd64) - Primary support
- aarch64 (arm64) - Full support for ARM servers/Apple Silicon
- armv7l (arm) - Limited support for embedded devices

### Offline Installation Flow
1. **Bundle Creation**: Downloads and packages all required components
2. **Offline Installation**: Installs bundled components without internet
3. **Arc Deployment**: Uses offline components for cluster registration

## Documentation Structure

- `docs/` - Comprehensive user documentation
- `memory-bank/` - Technical knowledge base and debugging patterns
- Root README.md - Primary user documentation with quickstart guide

## Development Notes

### Testing Requirements
- Test both online and offline modes
- Verify multi-architecture compatibility
- Validate on RHEL 9, Rocky Linux, CentOS Stream

### Git LFS Requirement
The repository requires Git LFS for offline bundles. Users must install git-lfs and run `git lfs pull` to download actual bundle files rather than pointer files.

### Bundle Management
Bundles are stored in `bundles/` directory with date-stamped filenames. The build script automatically generates SHA256 checksums for integrity validation during installation.

## Critical Design Patterns from Memory Bank

### DNS Troubleshooting Architecture
The most critical design pattern addresses VM environment issues:

**Problem Flow**: VM DNS Issues → CoreDNS Failures → Arc Certificate Problems → Connection Hangs

**Detection Pattern**:
```bash
# Test cluster internal DNS
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local

# Check Arc certificate issues  
kubectl describe pods -n azure-arc | grep -A5 -B5 "certificate\|MountVolume"
```

**Fix Pattern** (Critical Timing):
1. Apply CoreDNS fix with Cloudflare DNS (1.1.1.1, 1.0.0.1)
2. Restart CoreDNS deployment
3. **Wait 30 seconds** for DNS stabilization (critical timing)
4. Restart Arc agents with both `rollout restart` and `delete pod`
5. Wait 60+ seconds for certificate regeneration

### Sudo Credential Management Patterns

**Working Pattern** - Consolidated Commands:
```bash
sudo bash -c 'timedatectl set-ntp true; systemctl restart systemd-timesyncd'
```

**Failing Pattern** - Individual subprocess calls lose credential context:
```bash
execute_deployment_step "sudo dnf update -y" "Updating packages"  # Fails
```

**Root Cause**: Subprocess creation breaks cached sudo credential inheritance.

### User Experience Design Principles

**Visual Hierarchy** - Consistent indentation for progress:
```bash
# Main step
echo "[${step}/${total}] ${action}..."

# Substep level 1 (always visible)
echo "     ${ICON} ${substep_description}"

# Substep level 2 (important status)
echo "       ${STATUS_ICON} ${detailed_status}"

# Technical details (verbose only)
verbose_log "${technical_message}"
```

**Time Estimates** - Never promise specific times for complex operations like Arc connection (often takes 10-15+ minutes).

### Multi-Node Architecture Patterns

**High-Availability Requirements**:
- Minimum 3 server nodes for etcd quorum
- Load balancer for production clusters
- Proper network port configuration (6443, 10250, 8472, 2379-2380)

**Join Token Management**:
```bash
# Server deployment displays join information
./setup-k3s-arc.sh --status --node-role server  # Shows token for expansion

# Additional server nodes
./setup-k3s-arc.sh --node-role server --server-ip IP --join-token TOKEN

# Agent nodes  
./setup-k3s-arc.sh --node-role agent --server-ip IP --join-token TOKEN
```

### Offline Component Validation System

**Detection Logic**:
```bash
# Check completion marker first
check_offline_completion_marker()

# Validate individual components with version checks
validate_offline_helm()  # Tests helm version --short
validate_offline_kubectl()  # Tests kubectl version --client  
validate_offline_azure_cli()  # Tests az version with fallback to ~/.local/bin/az
```

**Dynamic Step Counting**:
- Offline mode: 8 steps (skips system updates, package installs, K3s install)
- Online mode: 14 steps (full installation)

### State Management Patterns

**Idempotent Operations**: State file `~/.k3s-arc-setup-state` tracks completion:
```bash
# Check completion status
is_completed "step_name"

# Mark step complete  
mark_completed "step_name"

# Reset state for re-runs
rm ~/.k3s-arc-setup-state
```

**Time Sync Re-verification**: Always verify time sync before Azure operations, even if previously completed.

### Error Handling Philosophy

**Graceful Degradation**: 
- DNS fixes continue with manual guidance if automatic fixes fail
- Component validation provides specific missing component lists
- Recovery procedures documented for emergency situations

**Environment-Specific Solutions**:
- VMware: Use Cloudflare DNS, enable VMware Tools time sync
- Corporate: Support custom DNS with Azure service fallbacks  
- Multi-arch: Detect and install appropriate binaries per architecture

### Command Line UX Patterns

**Flag Combinations**:
- `--offline` requires pre-installed bundle components
- `--print-ssh-key` incompatible with `--no-remote-management` 
- `--verbose` shows technical details, `--quiet` shows only errors
- `--diagnostics` and `--status` are informational modes

**Progressive Disclosure**:
- Standard output: Essential progress and outcomes
- Verbose mode: Technical implementation details
- Status mode: Current installation state and next steps