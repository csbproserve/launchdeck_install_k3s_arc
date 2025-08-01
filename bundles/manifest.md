# K3s Arc Offline Bundle Manifest

This directory contains offline installation bundles for the K3s + Azure Arc setup.

## Available Bundles


| k3s-arc-offline-install-bundle-20250801.tar.gz | 129M | 2025-08-01 | `0cc2aa68d2d1cd177ec435e83d112ac07abd6b2808e9796b4f9e9485b89dbd2e` | Multi-arch offline installation bundle |

*No bundles created yet. Use `build-k3s-arc-offline-install-bundle.sh` to create your first bundle.*

## Bundle Naming Convention
- Format: `k3s-arc-offline-install-bundle-YYYYMMDD.tar.gz`
- Example: `k3s-arc-offline-install-bundle-20250730.tar.gz`

## Bundle Contents
Each bundle contains:
- Helm binaries (all supported architectures)
- kubectl binaries (all supported architectures)
- Azure CLI Python wheels and dependencies
- Fresh get.k3s.io installation script
- Checksums for all components
- Installation manifest

## Usage
1. Build bundle: `./build-k3s-arc-offline-install-bundle.sh`
2. Install bundle: `./install-k3s-arc-offline-install-bundle.sh bundle-name.tar.gz`
3. Use offline: `./setup-k3s-arc.sh --offline [other-options]`

## Bundle Management
- Create new bundles with the build script
- Install bundles with the install script  
- Remove old bundles manually or with `build-k3s-arc-offline-install-bundle.sh --remove-bundle`
- Bundles are self-contained and can be transferred between systems

## Bandwidth Benefits
Offline bundles reduce outbound bandwidth requirements by pre-downloading:
- Helm: ~50MB download avoided
- kubectl: ~50MB download avoided  
- Azure CLI: ~200MB+ download avoided
- Total savings: ~300MB+ per installation
