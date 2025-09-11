Crossplane Function mTLS Authentication Issue

  Issue Description

  Crossplane functions (particularly function-patch-and-transform) fail to communicate with the Crossplane controller due to missing mTLS client certificates. This manifests as repeated gRPC connection failures.

  Symptoms

  - Crossplane logs show repeated errors like:
  rpc error: code = DeadlineExceeded desc = latest balancer error: last connection error:
  connection error: desc = "transport: Error while dialing: dial tcp 10.42.x.x:9443: connect: no route to host"
  - Functions appear as INSTALLED=True but HEALTHY=False or fail to install entirely
  - Crossplane pods stuck in Init:0/1 status with mount errors
  - Missing crossplane-tls-client secret in crossplane-system namespace

  Root Cause

  This is a certificate bootstrapping chicken-and-egg problem in Crossplane's certificate lifecycle management:

  1. The crossplane-tls-client secret gets deleted or corrupted
  2. Crossplane pods cannot start because they require this secret as a mounted volume
  3. Since Crossplane isn't running, it cannot regenerate the missing client certificates
  4. Without client certificates, mTLS authentication between Crossplane and functions fails

  This commonly occurs after:
  - Certificate cleanup operations
  - Crossplane upgrades/reinstalls
  - Manual certificate deletion
  - Cluster restart issues

  Diagnosis Commands

  # Check for missing certificates
  kubectl get secrets -n crossplane-system | grep -E 'crossplane-root-ca|crossplane-tls-client|function-patch-and-transform'

  # Check Crossplane pod status
  kubectl get pods -n crossplane-system -l app=crossplane

  # Check for mount errors
  kubectl describe pods -n crossplane-system -l app=crossplane | grep -A5 -B5 "Warning\|Error"

  # Check function status
  kubectl get functions

  # Check Crossplane logs for gRPC errors
  kubectl logs -n crossplane-system deployment/crossplane --tail=100 | grep -E "dial tcp.*9443|DeadlineExceeded|no route to host"

  Resolution

  Step 1: Create Dummy Client Certificate Secret

  # Create a placeholder secret to break the bootstrapping cycle
  kubectl create secret generic crossplane-tls-client -n crossplane-system \
    --from-literal=tls.crt="" \
    --from-literal=tls.key="" \
    --from-literal=ca.crt=""

  Step 2: Restart Crossplane Pods

  # Force restart of stuck Crossplane pods
  kubectl delete pods -n crossplane-system -l app=crossplane --force --grace-period=0

  # Wait for Crossplane to become available
  kubectl wait --for=condition=Available deployment/crossplane -n crossplane-system --timeout=300s

  Step 3: Verify Function Installation

  # Wait for function to be properly installed
  kubectl wait --for=condition=Installed function/function-patch-and-transform --timeout=300s

  # Verify function health
  kubectl get functions

  Step 4: Confirm Certificate Regeneration

  # Verify all required certificates are present
  kubectl get secrets -n crossplane-system | grep -E 'crossplane-root-ca|crossplane-tls-client|function-patch-and-transform'

  # Check for successful gRPC connection in logs
  kubectl logs -n crossplane-system deployment/crossplane --tail=20 | grep -i "function-patch-and-transform"

  Expected Success Indicators

  After resolution, you should see:
  - All three certificate secrets present: crossplane-root-ca, crossplane-tls-client, function-patch-and-transform-tls-server
  - Functions showing INSTALLED=True and HEALTHY=True
  - Crossplane logs showing successful gRPC connections:
  Created new gRPC client connection {"function": "function-patch-and-transform", "target": "dns:///function-patch-and-transform.crossplane-system:9443"}
  Successfully configured package revision
  Successfully installed package revision

  Prevention

  To avoid this issue in the future:
  - Avoid manually deleting certificate secrets in crossplane-system
  - When troubleshooting certificate issues, restart pods before deleting secrets
  - Use kubectl rollout restart instead of force-deleting pods when possible
  - Monitor certificate expiration and renewal processes

  Related Crossplane Issues

  This is a known issue documented in the Crossplane community:
  - https://github.com/crossplane/crossplane/issues/4707 - TLS certificate validation failures
  - https://github.com/crossplane/crossplane/issues/5456 - Certificate signed by unknown authority

  The issue typically affects Crossplane v1.14+ with function-based compositions using the Pipeline mode.
