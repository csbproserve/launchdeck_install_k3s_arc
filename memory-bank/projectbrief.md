# Project Brief: K3s + Azure Arc Automation

## Project Goal
Automate the deployment and management of K3s clusters with Azure Arc integration, specifically targeting VM environments (VMware, Rocky Linux, RHEL) where DNS and connectivity issues are common.

## Core Problems Being Solved
1. **VM DNS Issues**: VMware and virtualized environments frequently have DNS forwarding problems that prevent Azure Arc agents from generating certificates
2. **Arc Connection Hangs**: `az connectedk8s connect` operations hang for 15-20+ minutes due to DNS-related certificate generation failures
3. **Manual Intervention Required**: Current deployments require extensive manual troubleshooting and DNS fixes
4. **Inconsistent User Experience**: Multiple sudo password prompts and unclear progress indicators during setup

## Automation Scope
- **Primary Script**: `setup-k3s-arc.sh` - Complete K3s + Arc deployment automation
- **Target Environment**: Enterprise VM environments (VMware vSphere, Rocky Linux, RHEL)
- **Key Features**: Automatic DNS detection/fixes, sudo credential management, progress indicators
- **Expected Runtime**: 10-15 minutes for complete deployment

## Success Criteria
1. **Zero Manual Intervention**: Script handles DNS issues and Arc connection problems automatically
2. **Single Sudo Prompt**: User enters password once at script start
3. **Clear Progress**: User sees clear progress through 14 deployment steps
4. **Reliable Arc Connection**: No hanging on `az connectedk8s connect` operations
5. **Working Flux Integration**: Flux extension installs successfully after Arc connection

## Current Focus
**Recently Resolved**: Sudo credential inheritance problems causing multiple password prompts have been resolved with a secure single-prompt solution using memory-only password storage and post-time-sync credential refresh.

**Current Priority**: Testing and validation of the secure sudo solution across different VM environments (VMware, Rocky Linux, RHEL) and monitoring deployment reliability improvements.

**Environment**: Enterprise VM setups where DNS forwarding and certificate generation are primary failure points.