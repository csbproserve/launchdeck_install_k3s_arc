# Diagnostic Commands Reference

## Quick Health Check

### Overall Arc Status
```bash
# Check all Arc agent pods
kubectl get pods -n azure-arc

# Check for certificate issues
kubectl describe pods -n azure-arc | grep -A5 -B5 "certificate\|MountVolume"
```

### DNS Testing
```bash
# Test cluster internal DNS
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local

# Test external DNS from cluster
kubectl run external-dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup google.com
```

## Advanced Diagnostics

### CoreDNS Investigation
```bash
# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20

# Check current CoreDNS config
kubectl get configmap coredns -n kube-system -o yaml

# Monitor CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns -w
```

### Arc Agent Analysis
```bash
# Monitor Arc agent recovery
kubectl get pods -n azure-arc -w

# Check Arc agent logs for certificate errors
kubectl logs -n azure-arc -l app.kubernetes.io/component=connect-agent --tail=10

# Check cluster-metadata-service logs
kubectl logs -n azure-arc -l app.kubernetes.io/component=cluster-metadata-service --tail=10

# Check resource-sync-agent logs
kubectl logs -n azure-arc -l app.kubernetes.io/component=resource-sync-agent --tail=10
```

### Azure CLI Diagnostics
```bash
# Check Arc connection from Azure perspective
az connectedk8s show --name <cluster> --resource-group <rg> --subscription <sub>

# List Arc extensions
az k8s-extension list --cluster-name <cluster> --resource-group <rg> --cluster-type connectedClusters

# Check Flux extension specifically
az k8s-extension show --name flux --cluster-name <cluster> --resource-group <rg> --cluster-type connectedClusters
```

## Emergency Commands

### Quick DNS Fix
```bash
# Emergency DNS fix (one-liner)
kubectl patch configmap coredns -n kube-system --type merge -p='{"data":{"Corefile":".:53 {\n    errors\n    health {\n       lameduck 5s\n    }\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n       ttl 30\n    }\n    prometheus :9153\n    forward . 1.1.1.1 1.0.0.1\n    cache 30\n    loop\n    reload\n    loadbalance\n}\n"}}'
```

### Emergency Arc Agent Restart
```bash
# Restart CoreDNS and Arc agents
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout restart deployment -n azure-arc
kubectl delete pod -n azure-arc --all
```

### System-Level Diagnostics
```bash
# Check time synchronization
timedatectl status

# Check DNS resolution from host
nslookup kubernetes.default.svc.cluster.local

# Check K3s service status
systemctl status k3s

# Check network connectivity
curl -k https://kubernetes.default.svc.cluster.local:443
```

## Monitoring Commands

### Real-time Monitoring
```bash
# Watch Arc pods come online
watch kubectl get pods -n azure-arc

# Monitor CoreDNS restarts
kubectl rollout status deployment/coredns -n kube-system --timeout=90s

# Watch for certificate secrets
watch kubectl get secrets -n azure-arc | grep certificate
```

### Log Streaming
```bash
# Stream Arc agent logs
kubectl logs -n azure-arc -l app.kubernetes.io/component=connect-agent -f

# Stream CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns -f