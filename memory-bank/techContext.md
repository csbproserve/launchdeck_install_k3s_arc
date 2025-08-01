# Technical Context: Technologies & Environment

## Core Technologies

### K3s Kubernetes Distribution
- **Version**: Latest stable (lightweight Kubernetes)
- **Target Environment**: Single-node and small cluster deployments
- **Key Components**: 
  - CoreDNS for cluster DNS
  - Traefik ingress controller
  - Local storage provisioner
- **Benefits**: Minimal resource requirements, fast startup, enterprise-ready

### Azure Arc for Kubernetes
- **Purpose**: Connect on-premises K3s clusters to Azure management
- **Key Components**:
  - Arc agents (10-12 pods in azure-arc namespace)
  - Certificate management system
  - Azure connectivity and authentication
- **Requirements**: Outbound HTTPS access, working DNS, time synchronization

### Flux GitOps Extension
- **Purpose**: GitOps workflow automation
- **Dependency**: Requires fully connected Arc cluster
- **Installation**: Via Azure Arc extension mechanism

## Target Operating Systems

### Rocky Linux (Primary)
- **Versions**: 8.x, 9.x
- **Package Manager**: DNF/YUM
- **Key Services**: systemd, chronyd, firewalld
- **Common Issues**: SELinux policies, firewall rules

### Red Hat Enterprise Linux (RHEL)
- **Versions**: 8.x, 9.x  
- **Similar to**: Rocky Linux (RHEL rebuild)
- **Enterprise Features**: Support subscriptions, enhanced security
- **Common Issues**: Subscription management, SELinux

### VMware vSphere Integration
- **VM Templates**: Rocky Linux/RHEL on VMware
- **Network**: Often complex enterprise networking
- **DNS Issues**: VM DNS forwarding frequently misconfigured
- **Storage**: VMware virtual disks

## Command-Line Tools

### Required System Tools
```bash
# Kubernetes management
kubectl                 # Cluster management
k3s                     # Kubernetes distribution

# Azure connectivity  
az                      # Azure CLI
curl                    # HTTP operations

# System administration
sudo                    # Privilege escalation
systemctl               # Service management
timedatectl            # Time synchronization
firewall-cmd           # Firewall management
dnf/yum                # Package management
```

### Bash Scripting Technologies
```bash
# Script execution patterns
eval                    # Command execution
bash -c                 # Consolidated command execution
trap                    # Signal handling
read                    # User input

# Process management
&                       # Background processes
kill                    # Process termination
ps                      # Process listing
nohup                   # Background execution
```

## Network Requirements

### Outbound Connectivity
- **Azure Endpoints**: *.servicebus.windows.net, login.microsoftonline.com
- **Container Registries**: mcr.microsoft.com, ghcr.io
- **DNS Servers**: 1.1.1.1, 1.0.0.1 (reliable external DNS)
- **Ports**: 443/TCP (HTTPS), 53/UDP (DNS)

### Internal Cluster Networking
- **Service CIDR**: 10.43.0.0/16 (K3s default)
- **Pod CIDR**: 10.42.0.0/16 (K3s default)
- **Cluster DNS**: 10.43.0.10 (CoreDNS service IP)

## Environment Constraints

### Enterprise Limitations
- **Proxy Servers**: May require proxy configuration
- **Firewall Rules**: Outbound restrictions common
- **DNS Policies**: Corporate DNS servers often unreliable
- **Security Policies**: SELinux, AppArmor enforcement

### VM-Specific Challenges
- **DNS Forwarding**: VMware DNS often misconfigured
- **Time Drift**: VM time synchronization issues
- **Resource Limits**: CPU/memory constraints in VM environments
- **Network Latency**: Virtualized network performance

## Critical Technical Dependencies

### Dependency Chain
```
System Time Sync → DNS Resolution → Arc Authentication → Certificate Generation → Flux Installation
```

### Failure Points
1. **Time Synchronization**: Azure authentication requires accurate time
2. **DNS Resolution**: Certificate generation fails without working DNS
3. **Network Connectivity**: Arc agents need Azure endpoint access
4. **Credential Management**: Sudo session inheritance across subprocesses

## Debugging Technical Stack

### Kubernetes Diagnostics
```bash
kubectl get pods -n azure-arc              # Arc agent status
kubectl describe pods -n azure-arc         # Certificate issues
kubectl get configmap coredns -n kube-system  # DNS configuration
kubectl logs -n azure-arc <pod-name>       # Arc agent logs
```

### System Diagnostics
```bash
timedatectl status                          # Time synchronization
systemctl status chronyd                   # Time service
nslookup kubernetes.default.svc.cluster.local  # DNS test
firewall-cmd --list-all                    # Firewall rules
```

### Azure Connectivity
```bash
az connectedk8s show --name <cluster> --resource-group <rg>  # Arc status
az k8s-extension list --cluster-name <cluster> --resource-group <rg>  # Extensions
curl -s https://login.microsoftonline.com  # Azure connectivity
```

## Performance Considerations

### Resource Requirements
- **Minimum**: 2 CPU, 4GB RAM for K3s + Arc
- **Recommended**: 4 CPU, 8GB RAM for production
- **Storage**: 20GB minimum for system + container images

### Timing Expectations
- **K3s Installation**: 2-3 minutes
- **Arc Connection**: 3-5 minutes (with DNS working)
- **Flux Installation**: 1-2 minutes
- **Total Deployment**: 10-15 minutes target

### Optimization Strategies
- **DNS Preemptive Fix**: Apply in VM environments automatically
- **Parallel Operations**: Where safe (avoid credential issues)
- **Efficient Polling**: Reasonable timeouts and intervals
- **Resource Monitoring**: Check available resources before deployment