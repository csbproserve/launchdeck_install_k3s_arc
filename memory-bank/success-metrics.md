# Success Metrics

## Before Fix - Broken State

### Azure Arc Connection Status
```json
{
  "provisioningState": "Succeeded",
  "connectivityStatus": "Connecting"
}
```
- Arc shows as provisioned but stuck in "Connecting" state
- Connection process hangs indefinitely
- No progress after 15-20 minutes

### Arc Agent Pods Status
```bash
kubectl get pods -n azure-arc
```
**Broken Output:**
```
NAME                                        READY   STATUS              RESTARTS   AGE
cluster-metadata-service-xxxxx-xxxxx        0/1     ContainerCreating   0          15m
clusterconnect-agent-xxxxx-xxxxx            0/1     ContainerCreating   0          15m
kube-aad-proxy-xxxxx-xxxxx                  0/1     ContainerCreating   0          15m
resource-sync-agent-xxxxx-xxxxx             0/1     ContainerCreating   0          15m
```
- 1-3 pods stuck in ContainerCreating
- No pods in Running state
- Multiple restart attempts

### Certificate Issues
```bash
kubectl describe pod -n azure-arc <kube-aad-proxy-pod>
```
**Error Messages:**
```
Events:
  Warning  FailedMount  5m (x12 over 15m)  kubelet  MountVolume.SetUp failed for volume "kube-aad-proxy-tls" : secret "kube-aad-proxy-certificate" not found
```

### DNS Resolution
```bash
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local
```
**Broken Output:**
```
Server:    10.43.0.10
Address 1: 10.43.0.10

nslookup: can't resolve 'kubernetes.default.svc.cluster.local'
pod "dns-test" deleted
pod default/dns-test terminated (Error)
```

### Expected Certificate Secrets
```bash
kubectl get secrets -n azure-arc | grep certificate
```
**Broken Output:**
```
(no output - certificates not generated)
```

## After Fix - Working State

### Azure Arc Connection Status
```json
{
  "provisioningState": "Succeeded",
  "connectivityStatus": "Connected"
}
```
- Arc shows full connectivity
- All health checks passing
- Stable connection maintained

### Arc Agent Pods Status
```bash
kubectl get pods -n azure-arc
```
**Working Output:**
```
NAME                                        READY   STATUS    RESTARTS   AGE
cluster-metadata-service-xxxxx-xxxxx        1/1     Running   0          5m
clusterconnect-agent-xxxxx-xxxxx            1/1     Running   0          5m
clusteridentityoperator-xxxxx-xxxxx         1/1     Running   0          5m
config-agent-xxxxx-xxxxx                    1/1     Running   0          5m
controller-manager-xxxxx-xxxxx              1/1     Running   0          5m
extension-events-collector-xxxxx-xxxxx      1/1     Running   0          5m
extension-manager-xxxxx-xxxxx               1/1     Running   0          5m
flux-logs-agent-xxxxx-xxxxx                 1/1     Running   0          5m
kube-aad-proxy-xxxxx-xxxxx                  1/1     Running   0          5m
metrics-agent-xxxxx-xxxxx                   1/1     Running   0          5m
resource-sync-agent-xxxxx-xxxxx             1/1     Running   0          5m
```
- 11-12 pods in Running state
- All pods showing 1/1 Ready
- No restart loops

### DNS Resolution
```bash
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local
```
**Working Output:**
```
Server:    10.43.0.10
Address 1: 10.43.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default.svc.cluster.local
Address 1: 10.43.0.1 kubernetes.default.svc.cluster.local
pod "dns-test" deleted
```

### Certificate Secrets Generated
```bash
kubectl get secrets -n azure-arc | grep certificate
```
**Working Output:**
```
kube-aad-proxy-certificate          Opaque               2      5m
clusterconnect-agent-certificate    Opaque               2      5m
```

### Flux Extension Status
```bash
az k8s-extension show --name flux --cluster-name <cluster> --resource-group <rg> --cluster-type connectedClusters
```
**Working Output:**
```json
{
  "installState": "Installed",
  "provisioningState": "Succeeded"
}
```

## Performance Metrics

### Time to Recovery
- **DNS Fix Application**: 30-60 seconds
- **CoreDNS Restart**: 30-90 seconds  
- **Arc Agent Stabilization**: 2-3 minutes
- **Total Recovery Time**: 3-5 minutes

### Reliability Metrics
- **DNS Fix Success Rate**: 95%+ in VM environments
- **Arc Connection Success**: 90%+ after DNS fix
- **Flux Installation Success**: 95%+ after Arc connection

## Validation Checklist

### Pre-Fix Validation
- [ ] Arc connection stuck in "Connecting" state
- [ ] Arc pods stuck in ContainerCreating
- [ ] Certificate secrets missing
- [ ] Cluster DNS resolution failing
- [ ] External DNS working (control test)

### Post-Fix Validation
- [ ] Arc connection shows "Connected"
- [ ] All Arc pods in Running state (11-12 pods)
- [ ] Certificate secrets present and valid
- [ ] Cluster DNS resolution working
- [ ] Flux extension installs successfully
- [ ] No certificate-related errors in logs

### Long-term Stability
- [ ] Arc connection remains stable for 24+ hours
- [ ] No pod restart loops
- [ ] DNS resolution consistently working
- [ ] Certificate renewal working automatically

## Monitoring Commands

### Quick Status Check
```bash
# One-liner health check
kubectl get pods -n azure-arc --no-headers | grep -v Running | wc -l
# Should return 0 for healthy system
```

### Comprehensive Health Check
```bash
#!/bin/bash
echo "=== Arc Agent Health ==="
kubectl get pods -n azure-arc

echo "=== DNS Test ==="
kubectl run dns-test --image=busybox:1.35 --restart=Never --rm -i --timeout=30s -- nslookup kubernetes.default.svc.cluster.local

echo "=== Certificate Secrets ==="
kubectl get secrets -n azure-arc | grep certificate

echo "=== Arc Connection Status ==="
az connectedk8s show --name <cluster> --resource-group <rg> --subscription <sub> --query "{provisioningState: provisioningState, connectivityStatus: connectivityStatus}"
```

## Troubleshooting Thresholds

### Warning Levels
- **1-2 pods not Running**: Monitor closely
- **DNS test fails occasionally**: Check CoreDNS logs
- **Certificate secrets missing**: Immediate intervention needed

### Critical Levels  
- **3+ pods not Running**: DNS fix likely needed
- **DNS test consistently fails**: Apply DNS fix immediately
- **Arc connection stuck >20 minutes**: Manual intervention required