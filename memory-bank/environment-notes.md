# Environment-Specific Notes

## VMware Environments

### Characteristics
- Most common environment for DNS issues
- Default DNS forwarding often fails due to VM network configuration
- NAT networking can cause additional complications

### Recommendations
- **DNS Servers**: Use Cloudflare DNS (1.1.1.1) more reliable than Google DNS (8.8.8.8)
- **Network Configuration**: Ensure VM has proper DNS resolution to host
- **Time Sync**: VMware Tools time synchronization critical for Azure authentication

### Common Issues
- CoreDNS forwarding fails due to VM network isolation
- Arc agents cannot reach Azure endpoints for certificate generation
- Time drift between VM and host affects Azure token validation

## Rocky Linux 9/10

### System Requirements
- **Time Sync**: systemd-timesyncd or chronyd required for time synchronization
- **Firewall**: firewalld configuration needed for K3s ports
- **SELinux**: May require additional considerations for container operations

### Configuration Commands
```bash
# Enable time synchronization
sudo timedatectl set-ntp true
sudo systemctl enable systemd-timesyncd

# Configure firewall for K3s
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --reload

# Check SELinux status
sestatus
```

### Known Issues
- Default chronyd configuration may not sync properly
- Firewall rules can block K3s internal communication
- SELinux policies may prevent proper pod operations

## RHEL 9

### Subscription Requirements
- Valid Red Hat subscription needed for package updates
- EPEL repository may be required for additional packages

### Configuration
```bash
# Register system
sudo subscription-manager register
sudo subscription-manager attach --auto

# Enable required repositories
sudo subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms
sudo subscription-manager repos --enable=rhel-9-for-x86_64-appstream-rpms
```

### Differences from Rocky Linux
- Subscription manager integration
- Different default firewall rules
- More restrictive SELinux policies by default

## CentOS Stream

### Considerations
- Rolling release model means packages change frequently
- May have newer kernels that cause compatibility issues
- Package availability can vary

### Recommendations
- Test thoroughly before production deployment
- Pin specific package versions when possible
- Monitor for upstream changes that affect K3s

## ARM64/aarch64 Systems

### Known Issues
- **Azure CLI**: Compatibility issues possible on ARM64
- **Helm/kubectl**: Architecture mismatches may occur during installation
- **Arc Agents**: May have additional stability issues on ARM64

### Mitigation Strategies
```bash
# Verify architecture compatibility
uname -m
kubectl version --client
helm version

# Use architecture-specific images when available
kubectl set image deployment/coredns coredns=registry.k8s.io/coredns/coredns:v1.10.1 -n kube-system
```

### Testing Requirements
- More extensive testing required for ARM64 deployments
- Container image availability verification needed
- Performance testing recommended

## Cloud Environments

### AWS EC2
- Instance metadata service can interfere with Arc agents
- Security groups must allow K3s communication
- Time synchronization usually works well

### Azure VMs
- Azure metadata service conflicts possible
- Network security groups configuration critical
- Generally good compatibility with Arc

### Google Cloud Platform
- Metadata service considerations similar to AWS
- VPC firewall rules important
- Time synchronization reliable

## Container Platforms

### Docker Desktop
- DNS forwarding through host system
- Resource constraints can affect performance
- Not recommended for production Arc testing

### Podman
- Different networking model than Docker
- May require additional configuration
- Limited testing with Arc deployments

## Network Considerations

### NAT Environments
- DNS forwarding can be problematic
- Port forwarding may be required
- Time synchronization challenges

### Corporate Networks
- Proxy configuration often required
- Firewall rules for Azure endpoints
- DNS resolution through corporate servers

### Air-Gapped Environments
- Arc requires internet connectivity
- Private registry setup needed
- Certificate management complexity

## Performance Considerations

### Memory Requirements
- Minimum 2GB RAM for K3s + Arc
- 4GB+ recommended for stable operation
- Monitor memory usage during deployment

### CPU Requirements
- 2+ CPU cores recommended
- ARM64 may require more resources
- Monitor CPU usage during Arc connection

### Storage Requirements
- 20GB+ available disk space
- SSD recommended for better performance
- Monitor disk I/O during operations