# ZDM Proxy Troubleshooting Guide

## Connectivity Issues with Astra DB

### Problem
ZDM proxy fails to start with CrashLoopBackOff due to inability to connect to Astra DB.

### Root Cause
The demo environment (kind cluster) doesn't have internet access required to connect to Astra DB.

## Solutions

### Solution 1: Enable Internet Access (Production)

For production deployments, ensure your Kubernetes cluster has internet access:

```bash
# Test internet connectivity from within the cluster
kubectl run test-connectivity --image=alpine --rm -it -- /bin/sh
# Inside the pod:
# ping google.com
# nslookup cassandra.us-east-1.aws.datastax.com
```

### Solution 2: Configure Kind Cluster with Internet Access

```bash
# Create kind cluster with proper networking
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: zdm-demo
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 8080
  - containerPort: 30042
    hostPort: 9042
  - containerPort: 30043
    hostPort: 9043
networking:
  disableDefaultCNI: false
EOF
```

### Solution 3: Mock Astra for Demo (Local Testing)

Configure ZDM proxy to run in source-only mode for demonstration:

```bash
# Temporarily disable target cluster for demo
kubectl set env deployment/zdm-proxy \
  ZDM_PRIMARY_CLUSTER=ORIGIN \
  ZDM_READ_MODE=PRIMARY_ONLY \
  ZDM_TARGET_ENABLED=false
```

### Solution 4: Fix Astra Credentials

Verify Astra credentials are correct:

```bash
# Check secret contents
kubectl get secret zdm-proxy-secret -o yaml

# Update with correct credentials
kubectl create secret generic zdm-proxy-secret \
  --from-literal=astra-username="YOUR_ASTRA_USERNAME" \
  --from-literal=astra-password="YOUR_ASTRA_APP_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Solution 5: Validate Secure Connect Bundle

```bash
# Check if bundle is mounted correctly
kubectl exec deployment/zdm-proxy -- ls -la /etc/astra/

# Test bundle validity (requires internet)
kubectl exec deployment/zdm-proxy -- unzip -t /etc/astra/secure-connect.zip
```

## Verification Steps

### 1. Check ZDM Proxy Status
```bash
kubectl get pods -l app=zdm-proxy
kubectl logs -l app=zdm-proxy --tail=20
```

### 2. Test Connectivity
```bash
# From within cluster
kubectl run debug --image=alpine --rm -it -- /bin/sh
# ping external-dns-name-from-bundle
```

### 3. Validate Configuration
```bash
# Check all ZDM environment variables
kubectl get deployment zdm-proxy -o jsonpath='{.spec.template.spec.containers[0].env}' | jq '.'
```

## Demo Environment Workaround

For demonstration purposes without internet access:

```bash
# 1. Configure Phase A only (source cluster only)
kubectl set env deployment/zdm-proxy \
  ZDM_PRIMARY_CLUSTER=ORIGIN \
  ZDM_READ_MODE=PRIMARY_ONLY \
  ZDM_PHASE=A

# 2. Remove target cluster configuration temporarily
kubectl patch deployment zdm-proxy --type='json' -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/env", "value": {"name": "ZDM_TARGET_SECURE_CONNECT_BUNDLE_PATH"}}
]'

# 3. Test with API pointing to ZDM for Phase A only
kubectl patch deployment python-api -p='{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "python-api",
          "env": [
            {"name": "CASSANDRA_HOST", "value": "zdm-proxy-svc"},
            {"name": "ZDM_PHASE", "value": "A"}
          ]
        }]
      }
    }
  }
}'
```

This allows demonstration of ZDM proxy functionality without requiring Astra connectivity.