# Script Context: Why These Automation Scripts Exist

## Problems Being Solved

### 1. VM DNS Forwarding Issues
**Environment**: VMware vSphere, Rocky Linux, RHEL enterprise environments
**Problem**: DNS forwarding frequently broken in virtualized environments, preventing:
- Azure Arc agent certificate generation
- Cluster internal DNS resolution
- External connectivity for Arc agents

**Impact**: `az connectedk8s connect` hangs for 15-20+ minutes with no progress

### 2. Manual Intervention Requirements
**Current State**: Deployments require extensive manual troubleshooting:
- DNS configuration fixes
- Arc agent restarts
- Certificate regeneration
- Time synchronization fixes

**Goal**: Zero manual intervention - script handles all common issues automatically

### 3. Inconsistent User Experience
**Problems**:
- Multiple sudo password prompts throughout deployment
- Unclear progress indicators
- No visibility into what's happening during hangs
- Inconsistent error messages

**Solution**: Single sudo prompt, clear 14-step progress, verbose logging options

## How Deployment Should Work

### Ideal User Experience
1. User runs `./setup-k3s-arc.sh` with required parameters
2. Enters sudo password ONCE at start
3. Sees clear progress through 14 steps with visual indicators
4. Script automatically detects and fixes DNS issues
5. Arc connection completes without hangs
6. Flux extension installs successfully
7. Total time: 10-15 minutes

### Current vs. Target State
**Current**: Manual DNS fixes, multiple password prompts, connection hangs
**Target**: Automated detection/fixes, single password prompt, reliable completion

## Script Architecture Goals

### 1. Robust Error Handling
- Automatic detection of DNS issues
- Proactive fixes before problems occur
- Graceful degradation with clear error messages

### 2. Credential Management
- Single sudo authentication at start
- Background keep-alive for long operations
- No additional password prompts during execution

### 3. Progress Visibility
- Clear step-by-step progress (1/14, 2/14, etc.)
- Substep indentation for detailed operations
- Verbose mode for debugging

### 4. Environment Awareness
- Detect VM environments that need DNS fixes
- Apply appropriate configurations for Rocky Linux/RHEL
- Handle enterprise firewall and network constraints

## Key User Workflows

### Standard Deployment
```bash
./setup-k3s-arc.sh --resource-group myRG --cluster-name myCluster --subscription mySubscription
```

### Troubleshooting Mode
```bash
./setup-k3s-arc.sh --verbose --mode status
```

### DNS Fix Testing
```bash
./setup-k3s-arc.sh --enable-dns-fix --test-only
```

## Success Metrics
- **Zero hangs** on Arc connection
- **Single password prompt** for entire deployment
- **Sub-15 minute** total deployment time
- **Automatic recovery** from common DNS issues
- **Clear user feedback** at every step