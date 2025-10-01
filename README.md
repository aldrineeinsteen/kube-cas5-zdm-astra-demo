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

# Verify Cassandra is ready
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

### Step 2: Start API (Direct Cassandra Connection)

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
  -d '{"name": "Demo User", "email": "demo@example.com", "gender": "Other", "address": "Demo Address"}' | jq .

# Verify record was created
curl -s http://localhost:8080/users?limit=1 | jq .
```

### Step 3: Deploy ZDM Proxy (Origin-Only Mode)

Deploy ZDM proxy in origin-only mode and switch API to use ZDM service:

```bash
# Deploy ZDM proxy (custom build from source)
make zdm-custom

# Verify ZDM proxy is running
kubectl get pods -l app=zdm-proxy
kubectl logs -l app=zdm-proxy --tail=5

# Patch API to use ZDM service (using helper script)
./demo-helper.sh patch-api-zdm

# OR manually patch API to use ZDM service:
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
            {"name": "TABLE", "value": "users"}
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

### Step 4: Test Origin-Only Mode

Verify ZDM proxy routes all traffic to Cassandra only:

```bash
# Create test record through ZDM
curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "ZDM Origin Test", "email": "zdm-origin@example.com", "gender": "Other", "address": "ZDM Test"}' | jq .

# Verify record exists in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users WHERE email = 'zdm-origin@example.com';"
# Expected: 1 row

# Record should NOT exist in Astra DB yet (origin-only mode)
```

### Step 5: Create Astra DB Schema

**Important**: Create the keyspace and table in Astra DB before enabling dual-write mode:

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

### Step 6: Configure ZDM for Dual-Write Mode

Switch ZDM to dual-write mode (writes to both Cassandra and Astra DB):

```bash
# Update ZDM proxy to dual-write mode (using helper script)
./demo-helper.sh zdm-dual-write

# OR manually configure dual-write mode:
kubectl patch deployment zdm-proxy -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "zdm-proxy",
          "env": [
            {"name": "ZDM_READ_MODE", "value": "PRIMARY_ONLY"},
            {"name": "ZDM_WRITE_MODE", "value": "DUAL"}
          ]
        }]
      }
    }
  }
}'

# Verify dual-write mode is active
kubectl logs -l app=zdm-proxy --tail=10 | grep -i "dual\|write\|mode"
```

### Step 7: Test Dual-Write Mode

Verify writes go to both Cassandra and Astra DB:

```bash
# Create test record in dual-write mode
curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Dual Write Test", "email": "dual-write@example.com", "gender": "Other", "address": "Dual Write Test"}' | jq .

# Verify record exists in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users WHERE email = 'dual-write@example.com';"
# Expected: 1 row

# Record should now ALSO exist in Astra DB (dual-write mode)
# Note: Verification requires Astra DB access - see appendix for detailed validation
```

### Step 8: Switch to Target-Only Mode

Configure ZDM to route all traffic to Astra DB only:

```bash
# Update ZDM proxy to target-only mode (using helper script)
./demo-helper.sh zdm-target-only

# OR manually configure target-only mode:
kubectl patch deployment zdm-proxy -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "zdm-proxy",
          "env": [
            {"name": "ZDM_READ_MODE", "value": "TARGET_ONLY"},
            {"name": "ZDM_WRITE_MODE", "value": "TARGET_ONLY"}
          ]
        }]
      }
    }
  }
}'

# Test target-only mode
curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Target Only Test", "email": "target-only@example.com", "gender": "Other", "address": "Target Only"}' | jq .

# This record should only exist in Astra DB, not in Cassandra
```

### Step 9: Direct Astra Connection (Final Migration)

Remove ZDM proxy and connect API directly to Astra DB:

```bash
# Delete ZDM proxy
kubectl delete deployment zdm-proxy

# Update API to connect directly to Astra DB
# Note: This requires Astra DB endpoint configuration
# See appendix/PHASE_B_IMPLEMENTATION.md for detailed Astra direct connection setup

# Verify final migration
curl -s http://localhost:8080/ | jq .
# Expected: "connection_type": "Direct Astra DB"
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

## Additional Documentation

- **[Appendix](appendix/README.md)** - Detailed technical documentation
- **[Custom Build Guide](appendix/CUSTOM_BUILD_SUMMARY.md)** - ZDM proxy build from source
- **[Troubleshooting](appendix/TROUBLESHOOTING.md)** - Common issues and solutions

---

This demo showcases a complete zero-downtime migration workflow, demonstrating how applications can seamlessly transition from Cassandra to Astra DB through progressive ZDM configuration changes.