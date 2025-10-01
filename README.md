# Cassandra 5 Zero Downtime Migration Demo

This project demonstrates migrating from Apache Cassandra 5 to DataStax Astra DB using Zero Downtime Migrator (ZDM) on Kubernetes.

## Quick Start

```bash
# 1. Setup environment
cp .env.example .env  # Edit with your Astra DB credentials

# 2. Run complete demo flow
make setup cassandra data test-data api test-api zdm test-zdm sync test-sync phase-dual test-dual phase-astra test-astra cleanup

# 3. Clean up
make down
```

## Demo Flow

### Phase 1: Infrastructure Setup
```bash
make setup      # 🚀 Create kind cluster
make cassandra  # 🚀 Deploy Cassandra StatefulSet  
make data       # 🚀 Generate demo data (1000 records)
make test-data  # 🔍 Verify data in Cassandra
```

**Showcase Commands:**
```bash
# Check cluster status
kubectl get nodes
kubectl get pods

# Verify Cassandra data directly
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT * FROM demo.users LIMIT 3;"
```

### Phase 2: API Deployment
```bash
make api        # 🚀 Deploy Python API
make test-api   # 🔍 Test API connectivity
```

**Showcase Commands:**
```bash
# Test API health and connection mode
curl -s http://localhost:8080/ | jq .

# List users via API
curl -s http://localhost:8080/users?limit=5 | jq .

# Create a new user via API (Phase 2 - Direct Cassandra)
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Phase2 User","email":"phase2@example.com","gender":"Female","address":"Cassandra Direct St"}' | jq .

# Verify the new user appears
curl -s http://localhost:8080/users | jq '.[] | select(.name=="Phase2 User")'

# Check data directly in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE name='Phase2 User' ALLOW FILTERING;"

# Verify total count in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

# Check API is connecting to Cassandra directly
curl -s http://localhost:8080/ | jq .connection_mode
# Expected: "cassandra"
```

### Phase 3: ZDM Proxy Setup
```bash
make zdm        # 🚀 Deploy ZDM proxy
make test-zdm   # 🔍 Test ZDM proxy connection
```

**Showcase Commands:**
```bash
# Verify ZDM proxy is running
kubectl get pods -l app=zdm-proxy
kubectl logs -l app=zdm-proxy --tail=10

# If ZDM proxy shows ImagePullBackOff on ARM64, see Troubleshooting section

# Test API now uses ZDM proxy
curl -s http://localhost:8080/ | jq .connection_mode
# Expected: "zdm"

# Create a new user via API (Phase 3 - ZDM Proxy)
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Phase3 ZDM User","email":"phase3@example.com","gender":"Male","address":"ZDM Proxy Lane"}' | jq .

# Verify the new user through ZDM
curl -s http://localhost:8080/users | jq '.[] | select(.name=="Phase3 ZDM User")'

# Check data in Cassandra (origin cluster)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE name='Phase3 ZDM User' ALLOW FILTERING;"

# Verify total count in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

# Note: At this stage, data may not yet be in Astra DB (target cluster)
# ZDM is configured but data sync hasn't run yet

# Verify data access through ZDM
curl -s http://localhost:8080/users?limit=3 | jq .
```

### Phase 4: Data Synchronization
```bash
make sync       # 🚀 Run data synchronization (DSBulk)
make test-sync  # 🔍 Verify data count in both clusters
```

**Showcase Commands:**
```bash
# Monitor data sync job
kubectl get jobs
kubectl logs job/dsbulk-migrator-sync --tail=20

# Create a user during sync (Phase 4 - Post-Sync)
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Phase4 Sync User","email":"phase4@example.com","gender":"Other","address":"Data Sync Blvd"}' | jq .

# Verify the new user appears via API
curl -s http://localhost:8080/users | jq '.[] | select(.name=="Phase4 Sync User")'

# Check data count in Cassandra (origin)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

# Verify specific user in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE name='Phase4 Sync User' ALLOW FILTERING;"

# Check if data sync completed successfully
kubectl logs job/dsbulk-migrator-sync --tail=10 | grep -i "completed\|success\|error"

# Note: After successful sync, verify data in Astra DB via:
# - Astra DB Console (https://astra.datastax.com)
# - Direct CQL connection to Astra
# - Expected: All historical data (1000+ records) should now be in both clusters

# API still works through ZDM during/after sync
curl -s http://localhost:8080/users?limit=2 | jq .
```

### Phase 5: Dual-Write Mode
```bash
make phase-dual # 🚀 Switch to dual-write mode
make test-dual  # 🔍 Test dual-write functionality
```

**Showcase Commands:**
```bash
# Create a new user to test dual-write (Phase 5 - Dual Write)
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Phase5 Dual User","email":"phase5@example.com","gender":"Female","address":"Dual Write Ave"}' | jq .

# Verify the new user appears in API responses
curl -s http://localhost:8080/users | jq '.[] | select(.name=="Phase5 Dual User")'

# Check data in Cassandra (origin cluster)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE name='Phase5 Dual User' ALLOW FILTERING;"

# Verify total count in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

# Create another test user for dual-write verification
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Dual Write Test","email":"dualwrite@example.com","gender":"Male","address":"Both Clusters St"}' | jq .

# Check both users are accessible via API
curl -s http://localhost:8080/users | jq '.[] | select(.name | contains("Phase5") or contains("Dual Write"))'

# Verify in Cassandra
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE name IN ('Phase5 Dual User', 'Dual Write Test') ALLOW FILTERING;"

# Note: In dual-write mode, new data should appear in BOTH clusters:
# - Cassandra (origin): Verify above with kubectl commands
# - Astra DB (target): Check via Astra Console or direct CQL connection
# - Expected: Both 'Phase5 Dual User' and 'Dual Write Test' in both clusters

# Check ZDM is still active
curl -s http://localhost:8080/ | jq .connection_mode
# Expected: "zdm"
```

### Phase 6: Direct Astra Connection
```bash
make phase-astra # 🚀 Direct Astra connection (Phase 5)
make test-astra  # 🔍 Test direct Astra connection
```

**Showcase Commands:**
```bash
# Verify API now connects directly to Astra
curl -s http://localhost:8080/ | jq .connection_mode
# Expected: "astra"

# Test data access from Astra DB
curl -s http://localhost:8080/users?limit=5 | jq .

# Create a user directly in Astra (Phase 6 - Direct Astra)
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Phase6 Astra User","email":"phase6@example.com","gender":"Female","address":"Astra Cloud Blvd"}' | jq .

# Verify the Astra-only user via API
curl -s http://localhost:8080/users | jq '.[] | select(.name=="Phase6 Astra User")'

# Create another test user in Astra
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Cloud Native User","email":"cloudnative@example.com","gender":"Other","address":"DataStax Drive"}' | jq .

# List recent Astra users
curl -s http://localhost:8080/users | jq '.[] | select(.name | contains("Phase6") or contains("Cloud Native"))'

# Verify total user count in Astra (via API)
curl -s http://localhost:8080/users | jq 'length'

# Check Cassandra (should NOT have the new Astra-only users)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name FROM demo.users WHERE name='Phase6 Astra User' ALLOW FILTERING;" || echo "User not found in Cassandra (expected)"

# Check total count in Cassandra (should be less than Astra now)
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

# Note: Verify in Astra DB directly via:
# - Astra DB Console: https://astra.datastax.com
# - CQL Console in Astra: SELECT * FROM demo.users WHERE name='Phase6 Astra User';
# - Expected: New Phase6 users exist ONLY in Astra, not in Cassandra
```

### Phase 7: Cleanup
```bash
make cleanup    # 🧹 Remove ZDM proxy
make down       # 🧹 Teardown entire cluster
```

**Showcase Commands:**
```bash
# Verify ZDM proxy is removed
kubectl get pods -l app=zdm-proxy
# Expected: No resources found

# API still works directly with Astra
curl -s http://localhost:8080/ | jq .connection_mode
# Expected: "astra"

# Final verification
curl -s http://localhost:8080/users?limit=3 | jq .
```

## Prerequisites

- **Kind** (Kubernetes in Docker)
- **kubectl** (Kubernetes CLI) 
- **Podman** or Docker
- **curl** and **jq** for testing
- **DataStax Astra DB** account with:
  - Secure Connect Bundle
  - Application Token

### Platform Compatibility
- **x86_64/AMD64**: Full support with all ZDM proxy versions
- **ARM64/Apple Silicon**: Requires ZDM proxy v2.1.0 or custom build (see Troubleshooting)

### Resource Requirements
- **CPU**: 2 cores minimum
- **Memory**: 4GB RAM minimum
- **Storage**: 2GB free space

## Environment Configuration

Create `.env` file from template:
```bash
cp .env.example .env
```

Edit `.env` with your Astra DB credentials:
```bash
# Astra DB Configuration
ASTRA_SECURE_BUNDLE_PATH=./secure-connect-migration-cql-demo.zip
ASTRA_TOKEN_FILE_PATH=./migration-cql-demo-token.json

# ZDM Configuration
ZDM_VERSION=v2.3.4  # For x86_64/AMD64 
# ZDM_VERSION=v2.1.0  # For ARM64/Apple Silicon (if needed)
```

**Important for ARM64/Apple Silicon users**: If you encounter Docker image pull errors, change `ZDM_VERSION=v2.1.0` in your `.env` file.

## Project Structure

```
├── k8s/                  # Kubernetes manifests
│   ├── cassandra/        # Cassandra StatefulSet
│   ├── data-generator/   # Job to populate demo data  
│   ├── data-sync/        # DSBulk migration job
│   └── zdm-proxy/        # ZDM Proxy deployment with ARM64 Dockerfile
├── python-api/           # FastAPI service
├── scripts/              # All utility scripts
│   ├── build-zdm-arm64.sh        # ARM64 ZDM proxy build script
│   ├── update-zdm-phase.sh       # ZDM phase management
│   ├── demo-helper.sh            # Demo utilities
│   ├── patch-api-astra.sh        # API connection switching
│   ├── setup_astra_schema.py     # Astra DB schema setup
│   ├── setup_astra_table.py      # Astra DB table creation
│   ├── validate_astra_connection.py # Astra connection validation
│   ├── simple_astra_test.py      # Basic Astra testing
│   ├── test_astra_python39.py    # Python 3.9 compatibility test
│   ├── sync-data.py              # Manual data synchronization
│   └── README.md                 # Scripts documentation
├── scratch/              # Development/testing files
├── appendix/             # Additional documentation
├── Makefile             # Demo workflow commands with phase management
└── README.md            # This file
```

## API Endpoints

The Python API provides the following endpoints:

- `GET /` - Health check with connection info
- `GET /users` - List all users (with optional `?limit=N`)
- `POST /users` - Create new user
- `GET /users/{user_id}` - Get specific user
- `PUT /users/{user_id}` - Update user
- `DELETE /users/{user_id}` - Delete user

## Connection Modes

The API supports three connection modes via `CONNECTION_MODE` environment variable:

1. **`cassandra`** - Direct Cassandra connection
2. **`zdm`** - ZDM proxy connection (default)
3. **`astra`** - Direct Astra DB connection

## Testing the Demo

### Comprehensive curl Testing Commands

#### Health & Status Checks
```bash
# Check API health and connection mode
curl -s http://localhost:8080/ | jq .

# Quick status check
curl -s http://localhost:8080/ | jq '{status: .status, connection_mode: .connection_mode, total_users: .total_users}'
```

#### Data Operations
```bash
# List all users
curl -s http://localhost:8080/users | jq .

# List limited users with pretty formatting
curl -s http://localhost:8080/users?limit=5 | jq '.[] | {name: .name, email: .email}'

# Get specific user by ID (replace USER_ID)
curl -s http://localhost:8080/users/USER_ID | jq .
```

#### Create Test Data
```bash
# Create a test user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo User","email":"demo@example.com","gender":"Male","address":"123 Demo Street"}' | jq .

# Create multiple users for testing
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Smith","email":"alice@example.com","gender":"Female","address":"456 Test Ave"}'

curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Bob Johnson","email":"bob@example.com","gender":"Male","address":"789 Sample Blvd"}'
```

#### Update & Delete Operations
```bash
# Update a user (replace USER_ID)
curl -X PUT http://localhost:8080/users/USER_ID \
  -H "Content-Type: application/json" \
  -d '{"name":"Updated Name","email":"updated@example.com","gender":"Other","address":"New Address"}' | jq .

# Delete a user (replace USER_ID)
curl -X DELETE http://localhost:8080/users/USER_ID | jq .
```

#### Phase-Specific Testing
```bash
# During Cassandra phase - verify direct connection
curl -s http://localhost:8080/ | jq 'select(.connection_mode == "cassandra")'

# During ZDM phase - verify proxy connection
curl -s http://localhost:8080/ | jq 'select(.connection_mode == "zdm")'

# During Astra phase - verify cloud connection
curl -s http://localhost:8080/ | jq 'select(.connection_mode == "astra")'
```

#### Data Consistency Verification
```bash
# Count users through API
curl -s http://localhost:8080/users | jq 'length'

# Compare with direct Cassandra count
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"

# Search for specific test users
curl -s http://localhost:8080/users | jq '.[] | select(.name | contains("Demo"))'
```

### Verify Migration Phases

Each phase can be verified by checking the API health endpoint:
```bash
curl -s http://localhost:8080/ | jq .connection_mode
```

Expected responses:
- Phase 1-2: `"cassandra"`
- Phase 3-4: `"zdm"` 
- Phase 5-6: `"astra"`

## Troubleshooting

### Check component status
```bash
make status  # View all components
make logs    # View all logs
```

### Common issues

1. **ZDM proxy fails to start**: Check Astra credentials in `.env`
2. **API connection timeout**: Verify target service is ready
3. **Data sync fails**: Ensure both clusters are accessible
4. **ZDM proxy ImagePullBackOff on ARM64/Apple Silicon**: See ARM64 fix below

### Debug specific components
```bash
kubectl get pods                    # Check pod status
kubectl logs -l app=cassandra      # Cassandra logs
kubectl logs -l app=zdm-proxy      # ZDM proxy logs  
kubectl logs -l app=python-api     # API logs
```

### ARM64/Apple Silicon Support

**✅ Fully Supported**: This demo now includes automatic ARM64 compatibility!

The `make zdm` command automatically builds a local ARM64 ZDM proxy image using the official ARM64 binary from DataStax GitHub releases. No manual fixes needed!

**How it works**:
1. `make zdm` calls `make build-zdm` first
2. `scripts/build-zdm-arm64.sh` downloads the official ARM64 binary
3. Builds a local Docker image with ARM64 support
4. Loads the image into the kind cluster
5. Deploys using the local image

**Manual build** (if needed):
```bash
# Build ARM64 image manually
./scripts/build-zdm-arm64.sh

# Or use make target
make build-zdm
```

**Troubleshooting ARM64 issues**:
```bash
# Check if you're on ARM64
uname -m  # Should show "arm64"

# Check pod status
kubectl describe pod -l app=zdm-proxy
# Look for: "no match for platform in manifest: not found"

# If issues persist, rebuild the image
./scripts/build-zdm-arm64.sh
```

3. **Environment Configuration**:
The `ZDM_VERSION` in `.env` allows you to specify which version to use:
```bash
# In .env file
ZDM_VERSION=v2.3.4  # Latest version (may need ARM64 build)
# or
ZDM_VERSION=v2.1.0  # Older version with ARM64 support
```

4. **Verify the fix**:
```bash
# After applying the fix
kubectl get pods -l app=zdm-proxy
# Should show: Running status

kubectl logs -l app=zdm-proxy --tail=5
# Should show: "Proxy connected and ready to accept queries"
```

## DataStax ZDM Migration Phases

This demo implements the official DataStax 5-phase migration process:

1. **Phase 1**: Deploy ZDM Proxy (dual writes automatically active)
2. **Phase 2**: Migrate existing data from origin to target  
3. **Phase 3**: Enable async dual reads (optional testing)
4. **Phase 4**: Route primary reads to target cluster
5. **Phase 5**: Direct connection to target, decommission origin

## Architecture

```
[Client] → [Python API] → [ZDM Proxy] → [Cassandra]
                              ↓
                         [Astra DB]
```

**Migration Flow:**
- **Initial**: API → Cassandra directly
- **Phase 1-4**: API → ZDM Proxy → Both clusters  
- **Phase 5**: API → Astra DB directly

## Notes

- Demo uses `emptyDir` storage (not persistent)
- Data schema: `UUID, name, email, gender, address`
- All secrets managed via Kubernetes Secret objects
- ZDM proxy handles dual-write logic automatically when both clusters are configured