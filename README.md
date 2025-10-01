# Cassandra 5 Zero Downtime Migration Demo

This project demonstrates migrating from Apache Cassandra 5 to DataStax Astra DB using Zero Downtime Migrator (ZDM) on Kubernetes.

## Project Structure
- `k8s/cassandra/` - Cassandra 5 StatefulSet (demo storage only)
- `k8s/zdm-proxy/` - ZDM Proxy deployment with ConfigMap/Secret
- `k8s/data-generator/` - Job to populate demo data
- `python-api/` - FastAPI service for data operations
- `Makefile` - Main build and deployment commands

## Migration Workflow
**Official DataStax 6-Phase Migration Process:**
- **Phase 1**: Infrastructure Setup - Deploy Cassandra, generate data
- **Phase 2**: API Deployment - Direct Cassandra connection
- **Phase 3**: ZDM Proxy Setup - Deploy ZDM proxy, connect API to proxy
- **Phase 4**: Data Synchronization - Migrate existing data from origin to target
- **Phase 5**: Dual-Write Mode - Enable dual writes to both clusters
- **Phase 6**: Direct Astra Connection - Switch API to direct Astra DB connection

## Prerequisites
1. **Docker Desktop** with Kubernetes enabled
2. **kind** CLI tool
3. **kubectl** configured
4. **Astra DB** account with:
   - Database created
   - Application token generated
   - Secure Connect Bundle downloaded

## Setup
1. **Configure Astra DB credentials:**
```bash
cp .env.example .env
# Edit .env with your Astra DB credentials
```

2. **Place your Astra files in the project root:**
   - `secure-connect-migration-cql-demo.zip` (your secure connect bundle)
   - `migration-cql-demo-token.json` (your application token)

## Complete Demo Execution

### Phase 1: Infrastructure Setup
```bash
# Create kind cluster
make setup

# Deploy Cassandra StatefulSet
make cassandra

# Generate demo data (1000 users)
make data

# Verify infrastructure
kubectl get pods
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
# Expected: 1000 users
```

### Phase 2: API Deployment (Direct Cassandra)
```bash
# Deploy Python API
make api

# Test Phase 2: Direct Cassandra connection
curl -s http://localhost:8080/ | jq
# Expected: connection_mode: "cassandra"

# Create Phase 2 test user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase2 User",
    "email": "phase2@example.com", 
    "gender": "Female",
    "address": "Cassandra Direct St"
  }' | jq

# Verify in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
# Expected: 1001 users (1000 + Phase2)
```

### Phase 3: ZDM Proxy Setup
```bash
# Build and deploy ZDM proxy
make zdm

# Switch API to use ZDM proxy (using kubectl patch)
kubectl patch deployment python-api --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env", "value": [
    {"name": "CASSANDRA_HOST", "value": "zdm-proxy-svc"},
    {"name": "CASSANDRA_PORT", "value": "9042"},
    {"name": "CASSANDRA_USERNAME", "value": "cassandra"},
    {"name": "CASSANDRA_PASSWORD", "value": "cassandra"},
    {"name": "KEYSPACE", "value": "demo"},
    {"name": "TABLE", "value": "users"},
    {"name": "ASTRA_TOKEN", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-password"}}}
  ]}
]'

# Wait for deployment
kubectl rollout status deployment/python-api --timeout=60s

# Test Phase 3: ZDM proxy connection
curl -s http://localhost:8080/ | jq
# Expected: connection_type: "ZDM Proxy", target: "zdm-proxy-svc:9042"

# Create Phase 3 test user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase3 ZDM User",
    "email": "phase3@example.com",
    "gender": "Male", 
    "address": "ZDM Proxy Lane"
  }' | jq

# Verify in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
# Expected: 1002 users (1000 + Phase2 + Phase3)
```

### Phase 4: Data Synchronization
```bash
# Run data sync job
kubectl apply -f k8s/data-sync/dsbulk-sync-job.yaml

# Monitor sync progress
kubectl get jobs
kubectl logs job/dsbulk-migrator-sync --follow

# Wait for completion (approximately 2-3 minutes)
kubectl wait --for=condition=complete --timeout=300s job/dsbulk-migrator-sync

# Create Phase 4 test user after sync
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase4 Sync User",
    "email": "phase4@example.com",
    "gender": "Non-binary",
    "address": "Data Sync Blvd"
  }' | jq

# Verify in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
# Expected: 1003 users (1000 + Phase2 + Phase3 + Phase4)
```

### Phase 5: Dual-Write Mode

**Method 1: Gradual Configuration (Recommended - Prevents CrashLoopBackOff)**
```bash
# Step 1: Add target configuration without enabling dual-write modes
kubectl patch deployment zdm-proxy --type='json' -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "ZDM_TARGET_CLOUD_SECURE_CONNECT_BUNDLE_PATH", "value": "/app/secure-connect.zip"}}
]'

# Wait for deployment to stabilize and establish Astra connection
kubectl rollout status deployment/zdm-proxy --timeout=60s

# Step 2: Enable dual-write modes (now that Astra connection is established)
kubectl patch deployment zdm-proxy --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env", "value": [
    {"name": "ZDM_ORIGIN_CONTACT_POINTS", "value": "cassandra-svc"},
    {"name": "ZDM_ORIGIN_PORT", "value": "9042"},
    {"name": "ZDM_ORIGIN_USERNAME", "value": "cassandra"},
    {"name": "ZDM_ORIGIN_PASSWORD", "value": "cassandra"},
    {"name": "ZDM_TARGET_USERNAME", "value": "token"},
    {"name": "ZDM_TARGET_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-password"}}},
    {"name": "ZDM_TARGET_SECURE_CONNECT_BUNDLE_PATH", "value": "/etc/astra/secure-connect.zip"},
    {"name": "ZDM_TARGET_CLOUD_SECURE_CONNECT_BUNDLE_PATH", "value": "/app/secure-connect.zip"},
    {"name": "ZDM_PROXY_LISTEN_ADDRESS", "value": "0.0.0.0"},
    {"name": "ZDM_PROXY_LISTEN_PORT", "value": "9042"},
    {"name": "ZDM_READ_MODE", "value": "DUAL_ASYNC_ON_SECONDARY"},
    {"name": "ZDM_WRITE_MODE", "value": "DUAL_ASYNC_ON_SECONDARY"},
    {"name": "ZDM_LOG_LEVEL", "value": "DEBUG"}
  ]}
]'

# Wait for deployment to complete
kubectl rollout status deployment/zdm-proxy --timeout=120s

# If any pods are still crashlooping, clean them up:
kubectl get pods -l app=zdm-proxy
# Delete crashlooping pods if present:
kubectl delete pod zdm-proxy-6c4b647457-7v474
# Replace 'zdm-proxy-6c4b647457-7v474' with actual crashlooping pod name

# Create Phase 5 test user (dual-write)
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase5 Dual User",
    "email": "phase5@example.com",
    "gender": "Female",
    "address": "Dual Write Ave"
  }' | jq

# Verify in Cassandra (should be present)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT * FROM demo.users WHERE name = 'Phase5 Dual User' ALLOW FILTERING;"
# Expected: User should be present

# Verify in Astra DB (use CQL console)
# Expected: User should be present in both clusters
```

### Phase 6: Direct Astra Connection
```bash
# Switch API to direct Astra connection using kubectl patch
kubectl patch deployment python-api --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/env", "value": [
    {"name": "CONNECTION_MODE", "value": "astra"},
    {"name": "ASTRA_TOKEN", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-password"}}},
    {"name": "ASTRA_SECURE_BUNDLE_PATH", "value": "/app/secure-connect.zip"}
  ]}
]'

# Wait for deployment
kubectl wait --for=condition=available --timeout=60s deployment/python-api

# Test Phase 6: Direct Astra connection
curl -s http://localhost:8080/ | jq
# Expected: connection_mode: "astra", connection_type: "Direct Astra DB"

# Check logs to confirm connection
kubectl logs -l app=python-api | grep "Successfully connected to Astra DB"

# Create Phase 6 test user (Astra-only)  
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase6 Direct Astra",
    "email": "phase6@example.com",
    "gender": "Male",
    "address": "Direct Astra St"
  }' | jq

# Verify user is NOT in origin Cassandra (bypassed ZDM)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT * FROM demo.users WHERE name = 'Phase6 Direct Astra' ALLOW FILTERING;"
# Expected: 0 rows (user only in Astra DB)
```

## Data Consistency Validation
```bash
# Count users in origin Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
# Expected: 1004 users (all except Phase6 Astra-only user)

# Count users in Astra DB (via CQL console)
# Expected: 1005 users (all users including Phase6)

# Verify specific phase users in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE name IN ('Phase2 User', 'Phase3 ZDM User', 'Phase4 Sync User', 'Phase5 Dual User') ALLOW FILTERING;"

# Connection mode switching test
kubectl get deployment python-api -o jsonpath='{.spec.template.spec.containers[0].env}' | jq
```

## Essential Commands
```bash
make setup     # Create kind cluster
make cassandra # Deploy Cassandra StatefulSet  
make data      # Generate demo data  
make api       # Deploy Python API
make zdm       # Build and deploy ZDM proxy
make down      # Clean teardown
```

## Troubleshooting

### ZDM Proxy Issues
- **ImagePullBackOff on ARM64**: Proxy builds locally for ARM64 compatibility
- **Connection failures**: Check Astra credentials in Secret
- **CrashLoopBackOff during dual-write config**: Delete crashlooping pods, existing pod continues working
- **Phase switching**: Use kubectl patch commands for precise control

### API Connection Issues  
- **Environment variables**: Use `kubectl describe pod` to check configuration
- **Secret keys**: Verify `zdm-proxy-secret` contains `astra-password` key (not `token`)
- **Bundle path**: Use `ASTRA_SECURE_BUNDLE_PATH` (not `ASTRA_BUNDLE_PATH`)

### Data Sync Issues
- **Job failures**: Check DSBulk logs with `kubectl logs job/dsbulk-migrator-sync`
- **Timeout**: Increase job timeout in dsbulk-sync-job.yaml
- **Credentials**: Verify Astra token has sufficient permissions

### API Validation Issues
- **Gender field**: Use exact values: `Male`, `Female`, `Non-binary`, `Prefer not to say`
- **API pagination**: Default limit may restrict results, use query parameters if needed

## Architecture
```
[Client] → [Python API] → [ZDM Proxy] → [Origin: Cassandra]
                             ↓
                        [Target: Astra DB]
```

**Phase Evolution:**
1. **Direct Cassandra**: Client → API → Cassandra
2. **ZDM Proxy**: Client → API → ZDM → Cassandra + Astra  
3. **Direct Astra**: Client → API → Astra

## Notes
- Demo uses `emptyDir` storage (not persistent)
- Data schema: `UUID, name, email, gender, address`  
- All secrets managed via Kubernetes Secret objects
- Use kubectl patch commands for deployment updates
- Gender field validation enforced by API
- ZDM proxy may require manual pod cleanup during mode switching

## Validated Migration Results
This demo successfully demonstrates:

✅ **Phase 1**: Infrastructure setup with 1000 demo users  
✅ **Phase 2**: Direct Cassandra API connection (+1 user = 1001 total)  
✅ **Phase 3**: ZDM proxy deployment and connection (+1 user = 1002 total)  
✅ **Phase 4**: Data synchronization to Astra DB (+1 user = 1003 total)  
✅ **Phase 5**: Dual-write mode validation (+1 user = 1004 total)  
✅ **Phase 6**: Direct Astra connection (+1 user = 1005 in Astra only)  

**Final State**: 
- Origin Cassandra: 1004 users
- Target Astra DB: 1005 users (complete migration + new Astra-only data)
- Zero downtime achieved throughout migration process

**Key Validations Confirmed:**
- Phase5 Dual User: Present in both Cassandra AND Astra (dual-write working)
- Phase6 Direct Astra: Only in Astra DB (direct connection working)
- All kubectl patch operations successful for deployment updates