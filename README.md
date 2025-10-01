# Cassandra 5 Zero Downtime Migration Demo

This project demonstrates a complete zero-downtime migration from Apache Cassandra 5 to DataStax Astra DB using the Zero Downtime Migrator (ZDM) proxy.

## Demo Overview

The demo follows a structured progression through migration phases:

1. **Cassandra Setup** - Deploy Cassandra with populated data
2. **Direct API Connection** - API connects directly to Cassandra (no ZDM)
3. **ZDM Origin-Only** - Deploy ZDM proxy, route API through proxy (reads/writes to Cassandra only)
4. **ZDM Dual-Write** - Configure ZDM for dual writes (Cassandra + Astra DB)
5. **ZDM Target-Only** - Switch to target-only mode (Astra DB only)
6. **Direct Astra Connection** - Remove ZDM, connect API directly to Astra DB

## Prerequisites

- **Podman** (Container runtime)
- **kubectl** (Kubernetes CLI)
- **kind** (Kubernetes in Docker)
- **Make** (Build automation)
- **curl** & **jq** (For testing)

### Resource Requirements

**Docker Desktop Settings** (recommended):
- **Memory**: 6GB minimum (8GB preferred)
- **CPUs**: 4 cores minimum
- **Disk**: 20GB free space

## Quick Setup

### 1. Environment Configuration

```bash
git clone <repository-url>
cd kube-cas5-zdm-astra-demo

# Configure environment
cp .env.example .env
# Edit .env with your Astra DB credentials:
# - ASTRA_SECURE_BUNDLE_PATH: Path to secure connect bundle
# - ASTRA_TOKEN_FILE_PATH: Path to application token JSON
# - ZDM_VERSION: ZDM proxy version (default: v2.3.4)
```

### 2. Start Infrastructure

```bash
# Create kind cluster and deploy Cassandra
make up

# Generate demo data (1000 records)
make data

# Deploy API
make api

# Verify everything is ready
make status
```

---

## Demo Walkthrough

### Step 1: Verify Cassandra with Data

Confirm Cassandra is running with populated data:

```bash
# Check Cassandra status
kubectl get pods -l app=cassandra

# Verify data count
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
# Expected: 1000 rows

# Sample data
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT id, name, email FROM demo.users LIMIT 3;"
```

### Step 2: Create Astra DB Schema

**Important**: Create the keyspace and table in Astra DB **BEFORE** deploying ZDM proxy, as ZDM Phase 1 immediately starts dual-write operations:

1. Login to [Astra DB Console](https://astra.datastax.com/)
2. Open your database → **CQL Console**
3. Execute the following commands:

```cql
-- Create keyspace (if not exists)
CREATE KEYSPACE IF NOT EXISTS demo 
WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'datacenter1': 1};

-- Create table with same structure as Cassandra
CREATE TABLE IF NOT EXISTS demo.users (
    id UUID PRIMARY KEY,
    name TEXT,
    email TEXT,
    gender TEXT,
    address TEXT
);
```

### Step 3: Start API (Direct Cassandra Connection)

Deploy API connecting directly to Cassandra service (default configuration):

```bash
# Deploy API
make api

# Verify API is healthy and connected to Cassandra
curl -s http://localhost:8080/ | jq .
# Expected: "target": "cassandra-svc:9042", "connection_type": "Direct Cassandra"

# Test API functionality
curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Demo User", "email": "demo@example.com", "gender": "Male", "address": "Demo Address"}' | jq .

# Verify record was created
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT id, name, email FROM demo.users WHERE email = 'demo@example.com' ALLOW FILTERING;"
```

### Step 4: Deploy ZDM Proxy (Phase 1 - Dual Write Mode)

Deploy ZDM proxy in DataStax Phase 1 configuration. **Important**: When both origin and target clusters are configured, ZDM automatically activates dual-write logic per DataStax specifications:

```bash
# Deploy ZDM proxy
make zdm

# Verify ZDM proxy is running
kubectl get pods -l app=zdm-proxy
kubectl logs -l app=zdm-proxy --tail=10

# Switch API to use ZDM proxy:
kubectl patch deployment python-api -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "python-api",
          "env": [
            {"name": "CASSANDRA_HOST", "value": "zdm-proxy-svc"},
            {"name": "CASSANDRA_PORT", "value": "9042"},
            {"name": "CASSANDRA_USERNAME", "value": "cassandra"},
            {"name": "CASSANDRA_PASSWORD", "value": "cassandra"},
            {"name": "KEYSPACE", "value": "demo"},
            {"name": "TABLE", "value": "users"},
            {"name": "ASTRA_TOKEN", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-password"}}}
          ]
        }]
      }
    }
  }
}'

# Verify API now connects through ZDM
curl -s http://localhost:8080/ | jq .
# Expected: "target": "zdm-proxy-svc:9042", "connection_type": "ZDM Proxy"
```

### Step 5: Test DataStax Phase 1 Behavior (Dual-Write Mode)

**Important**: DataStax ZDM Phase 1 automatically performs dual writes to both clusters when target configuration is present. This is correct behavior per DataStax documentation:

```bash
# Create test record through ZDM
curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "ZDM Phase 1 Test", "email": "zdm-phase1@example.com", "gender": "Female", "address": "ZDM Test"}' | jq .

# Verify record exists in Cassandra (origin)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users WHERE email = 'zdm-phase1@example.com' ALLOW FILTERING;"
# Expected: 1 row

# Record will ALSO exist in Astra DB (target) due to Phase 1 dual-write behavior
# This is correct per DataStax ZDM specifications
```

### Step 6: Phase 2 - Migrate Existing Data (DSBulk Migrator)

Use DataStax DSBulk Migrator to synchronise existing data from Cassandra to Astra DB:

```bash
# Run DSBulk Migrator for Phase 2 data migration
make sync

# Monitor the migration job
kubectl logs job/dsbulk-sync-job -f

# Verify data count in both systems after migration
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
# Check Astra DB count in the console - both should match
```

**Expected Output**: DSBulk Migrator will export data from Cassandra and import to Astra DB. Look for:
- Export performance: ~300 reads/second from Cassandra
- Import performance: ~80 writes/second to Astra DB
- Final message: "Migration completed successfully"

### Step 7: Phase 4 - Switch to Target Cluster (Complete Example)

This demonstrates switching ZDM to read from Astra DB as the primary cluster while maintaining dual writes.

#### Step 7.1: Check Current Configuration

First, verify the current ZDM configuration and data consistency:

```bash
# Check current ZDM environment variables
kubectl exec deployment/zdm-proxy -- env | grep ZDM_
# Expected output:
# ZDM_READ_MODE=PRIMARY_ONLY
# ZDM_WRITE_MODE=PRIMARY_ONLY  
# ZDM_PRIMARY_CLUSTER=ORIGIN (or not set, defaults to ORIGIN)

# Verify data count consistency between clusters
echo "=== Cassandra (Origin) Count ==="
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

echo "=== Test current read behavior (should read from Cassandra) ==="
curl -s http://localhost:8080/users?limit=3 | jq '.data[] | {id, name, email}'
```

#### Step 7.2: Switch to Phase 4 Configuration

Update ZDM to use Astra DB as the primary read cluster:

```bash
# Apply Phase 4 configuration - reads from target (Astra DB), writes to both
kubectl patch deployment zdm-proxy -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "zdm-proxy",
          "env": [
            {"name": "ZDM_READ_MODE", "value": "PRIMARY_ONLY"},
            {"name": "ZDM_WRITE_MODE", "value": "DUAL_WRITE"},
            {"name": "ZDM_PRIMARY_CLUSTER", "value": "TARGET"}
          ]
        }]
      }
    }
  }
}'

# Wait for rollout to complete (this may take 30-60 seconds)
echo "Waiting for ZDM proxy rollout..."
kubectl rollout status deployment/zdm-proxy --timeout=120s

# Verify the configuration was applied
kubectl exec deployment/zdm-proxy -- env | grep ZDM_
# Expected output:
# ZDM_READ_MODE=PRIMARY_ONLY
# ZDM_WRITE_MODE=DUAL_WRITE
# ZDM_PRIMARY_CLUSTER=TARGET
```

#### Step 7.3: Verify Phase 4 Behavior

Test that reads are now coming from Astra DB while writes still go to both:

```bash
# Test read behavior - should now read from Astra DB (target)
echo "=== Testing reads (should come from Astra DB now) ==="
curl -s http://localhost:8080/users?limit=5 | jq '{
  total_count: .total_count,
  first_user: .data[0] | {id, name, email},
  connection_info: {target: .target, connection_type: .connection_type}
}'

# Test write behavior - should still write to both clusters
echo "=== Testing Phase 4 dual-write behavior ==="
curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase 4 Test User", 
    "email": "phase4-test@example.com", 
    "gender": "Female", 
    "address": "Phase 4 Test Address"
  }' | jq .

# Verify the record was written to both clusters
echo "=== Verifying dual-write to Cassandra (Origin) ==="
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users WHERE email = 'phase4-test@example.com' ALLOW FILTERING;"
# Expected: 1 row

echo "=== Record should also exist in Astra DB (check via console or API) ==="
curl -s "http://localhost:8080/users?email=phase4-test@example.com" | jq .
# Expected: Should return the created record
```

#### Step 7.4: Performance and Monitoring

Monitor the Phase 4 configuration:

```bash
# Check ZDM proxy logs for any errors or warnings
kubectl logs -l app=zdm-proxy --tail=20

# Monitor API response times (reads now come from Astra DB)
time curl -s http://localhost:8080/users?limit=10 > /dev/null

# Check pod resource usage
kubectl top pods -l app=zdm-proxy
```

#### Step 7.5: Rollback (if needed)

If you need to revert to Phase 1 configuration:

```bash
# Rollback to Phase 1 - reads from origin (Cassandra)
kubectl patch deployment zdm-proxy -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "zdm-proxy",
          "env": [
            {"name": "ZDM_READ_MODE", "value": "PRIMARY_ONLY"},
            {"name": "ZDM_WRITE_MODE", "value": "DUAL_WRITE"},
            {"name": "ZDM_PRIMARY_CLUSTER", "value": "ORIGIN"}
          ]
        }]
      }
    }
  }
}'

kubectl rollout status deployment/zdm-proxy
echo "Reverted to Phase 1 - reads from Cassandra (origin)"
```

### Step 8: Understanding ZDM Configuration

**Important ZDM Behavior**: The current configuration shows environment variables:
- `ZDM_READ_MODE=PRIMARY_ONLY` 
- `ZDM_WRITE_MODE=PRIMARY_ONLY`

However, per DataStax documentation, when ZDM proxy is deployed with both origin and target cluster configurations, **dual-write logic is automatically activated** regardless of these environment variable settings. This is Phase 1 behavior by design.

To verify this is working correctly:

```bash
# Check ZDM proxy logs for connection confirmations
kubectl logs -l app=zdm-proxy --tail=20

# Look for messages like:
# "Initialized origin control connection. Cluster Name: ..."
# "Initialized target control connection. Cluster Name: ..."
# "Proxy connected and ready to accept queries on ..."

# Check ZDM configuration status
kubectl exec deployment/zdm-proxy -- cat /proc/1/environ | tr '\0' '\n' | grep ZDM
```

### Step 7: Official DataStax Migration Process

This demo currently demonstrates **Phase 1** of the official DataStax 5-phase migration process:

#### **Phase 1: Deploy ZDM Proxy (CURRENT STATE)**
- ✅ **Dual writes automatically active** when both clusters are configured
- ✅ Reads from primary (origin) cluster only
- ✅ All writes go to both origin and target clusters
- ✅ Zero downtime for client applications

#### **Complete DataStax Migration Phases:**

**Phase 2: Migrate Existing Data**
- Use DataStax tools to copy existing data from origin to target
- Validate data consistency between clusters
- Reconcile any differences

**Phase 3: Enable Async Dual Reads (Optional)**
- Configure `read_mode: DUAL_ASYNC_ON_SECONDARY`
- Test target cluster performance with production read load
- Monitor and optimize target cluster

**Phase 4: Route Reads to Target**
- Set `primary_cluster: TARGET` 
- All reads now served by target cluster
- Writes continue to both clusters

**Phase 5: Direct Connection to Target**
- Remove ZDM proxy
- Connect applications directly to target cluster
- Decommission origin cluster

### Step 8: Advanced Configuration (Optional)

For production environments, you can demonstrate additional phases:

```bash
# Example: Enable async dual reads (Phase 3)
kubectl patch deployment zdm-proxy -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "zdm-proxy",
          "env": [
            {"name": "ZDM_READ_MODE", "value": "DUAL_ASYNC_ON_SECONDARY"}
          ]
        }]
      }
    }
  }
}'

# Example: Switch primary cluster to target (Phase 4)
kubectl patch deployment zdm-proxy -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "zdm-proxy",
          "env": [
            {"name": "ZDM_PRIMARY_CLUSTER", "value": "TARGET"}
          ]
        }]
      }
    }
  }
}'

# This record should only exist in Astra DB, not in Cassandra
```

### Step 9: Phase 5 - Direct Astra Connection (Final Migration)

Complete the migration by removing ZDM proxy and connecting API directly to Astra DB:

#### Step 9.1: Verify Current State

Before final migration, confirm ZDM Phase 4 is working correctly:

```bash
# Check current API connection (should be through ZDM proxy)
curl -s http://localhost:8080/ | jq .
# Expected: "target": "zdm-proxy-svc:9042", "connection_type": "ZDM Proxy"

# Verify data exists in Astra DB
curl -s http://localhost:8080/users?limit=3 | jq '.data[] | {id, name, email}'
```

#### Step 9.2: Configure API for Direct Astra Connection

Update the API to connect directly to Astra DB using the secure connect bundle:

```bash
# Patch API deployment to use direct Astra DB connection
kubectl patch deployment python-api -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "python-api",
          "env": [
            {"name": "CONNECTION_MODE", "value": "astra"},
            {"name": "ASTRA_SECURE_BUNDLE_PATH", "value": "/app/secure-connect-bundle.zip"},
            {"name": "ASTRA_CLIENT_ID", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-username"}}},
            {"name": "ASTRA_CLIENT_SECRET", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-password"}}},
            {"name": "KEYSPACE", "value": "demo"},
            {"name": "TABLE", "value": "users"}
          ],
          "volumeMounts": [
            {"name": "astra-bundle", "mountPath": "/app", "readOnly": true}
          ]
        }],
        "volumes": [
          {"name": "astra-bundle", "secret": {"secretName": "zdm-proxy-secret", "items": [{"key": "secure-connect-bundle", "path": "secure-connect-bundle.zip"}]}}
        ]
      }
    }
  }
}'

# Wait for API rollout to complete
kubectl rollout status deployment/python-api --timeout=120s
```

#### Step 9.3: Verify Direct Astra Connection

Test that API now connects directly to Astra DB:

```bash
# Check API health and connection type
curl -s http://localhost:8080/ | jq .
# Expected: "connection_type": "Direct Astra DB"

# Test data access through direct connection
curl -s http://localhost:8080/users?limit=5 | jq '{
  total_count: .total_count,
  connection_info: {target: .target, connection_type: .connection_type},
  sample_users: .data[0:2] | [.[] | {id, name, email}]
}'

# Test write functionality (should only write to Astra DB now)
curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Direct Astra Test", 
    "email": "direct-astra@example.com", 
    "gender": "Female", 
    "address": "Direct Astra Address"
  }' | jq .
```

#### Step 9.4: Remove ZDM Proxy (Decommission)

Once direct Astra connection is verified, remove ZDM proxy:

```bash
# Delete ZDM proxy deployment and service
kubectl delete deployment zdm-proxy
kubectl delete service zdm-proxy-svc
kubectl delete configmap zdm-proxy-config

# Verify ZDM resources are removed
kubectl get pods -l app=zdm-proxy
# Expected: No resources found

# Final verification - record should only exist in Astra DB
echo "=== Testing direct Astra DB connection ==="
curl -s "http://localhost:8080/users?email=direct-astra@example.com" | jq .

# Cassandra should NOT have the new record (ZDM proxy removed)
echo "=== Verifying Cassandra doesn't have new record ==="
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users WHERE email = 'direct-astra@example.com' ALLOW FILTERING;"
# Expected: 0 rows (record only in Astra DB)
```

#### Step 9.5: Optional - Decommission Cassandra

If migration is complete, you can also remove the original Cassandra cluster:

```bash
# Optional: Remove Cassandra (only after confirming all data is in Astra DB)
# WARNING: This will permanently delete all Cassandra data
# kubectl delete statefulset cassandra
# kubectl delete service cassandra-svc
# kubectl delete pvc data-cassandra-0

echo "Migration to Astra DB completed successfully!"
echo "API now connects directly to Astra DB without ZDM proxy"
```

---

## Verification Commands

### Check System Status
```bash
make status
```

### View Logs
```bash
# API logs
kubectl logs -l app=python-api --tail=20

# ZDM proxy logs
kubectl logs -l app=zdm-proxy --tail=20

# Cassandra logs
kubectl logs cassandra-0 --tail=20
```

### Data Validation
```bash
# Count records in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

# Check API health
curl -s http://localhost:8080/health | jq .
```

---

## Clean Up

```bash
# Teardown entire demo environment
make down
```

---

## Available Make Targets

| Target | Description |
|--------|-------------|
| `make up` | Start kind cluster and deploy Cassandra |
| `make data` | Generate demo data (1000 records) |
| `make api` | Deploy Python API service |
| `make zdm-custom` | Build and deploy custom ZDM proxy |
| `make status` | Check status of all components |
| `make logs` | Show logs from all components |
| `make down` | Teardown kind cluster |

---

## Project Structure

```
├── k8s/                          # Kubernetes manifests
│   ├── cassandra/               # Cassandra StatefulSet
│   ├── data-generator/          # Demo data generation job
│   ├── python-api/             # FastAPI service
│   └── zdm-proxy/              # ZDM proxy configurations
├── python-api/                  # API source code
├── demo-helper.sh              # Demo automation script
├── .env.example                # Environment configuration template
├── Makefile                    # Build automation
├── appendix/                   # Detailed technical documentation
└── scratch/                    # Test files and development scripts
```

---

## Demo Cleanup

After completing the demo, clean up remote Astra DB data:

### Clear Demo Data
1. Login to [Astra DB Console](https://astra.datastax.com/)
2. Open your database → **CQL Console**
3. Execute: `TRUNCATE demo.users;`

### Complete Reset (Optional)
⚠️ **Warning**: This removes the entire keyspace and all tables.

```cql
DROP KEYSPACE demo;
```

---

## Troubleshooting

### Memory Issues

If you see `Insufficient memory` errors or pods stuck in `Pending` state:

1. **Check current memory usage:**
   ```bash
   kubectl describe node zdm-demo-control-plane | grep -A 10 "Allocated resources"
   ```

2. **If memory usage is >95%, increase container runtime resources:**
   - **Docker Desktop**: Settings → Resources → Advanced → Memory (6-8GB)
   - **Podman Desktop**: Settings → Resources → Memory (6-8GB)

3. **Temporary workaround** (reduce resource requests):
   ```bash
   kubectl rollout undo deployment/python-api  # Revert failed rollout
   ```

### Deployment Rollout Issues

If `./demo-helper.sh patch-api-zdm` times out:
```bash
kubectl rollout undo deployment/python-api    # Revert to working state
kubectl rollout status deployment/python-api  # Wait for completion
```

## Additional Documentation

- **[Appendix](appendix/README.md)** - Detailed technical documentation
- **[Custom Build Guide](appendix/CUSTOM_BUILD_SUMMARY.md)** - ZDM proxy build from source
- **[Troubleshooting](appendix/TROUBLESHOOTING.md)** - Common issues and solutions

---

This demo showcases a complete zero-downtime migration workflow, demonstrating how applications can seamlessly transition from Cassandra to Astra DB through progressive ZDM configuration changes.