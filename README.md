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

### Phase 2: API Deployment
```bash
make api        # 🚀 Deploy Python API
make test-api   # 🔍 Test API connectivity
```

### Phase 3: ZDM Proxy Setup
```bash
make zdm        # 🚀 Deploy ZDM proxy
make test-zdm   # 🔍 Test ZDM proxy connection
```

### Phase 4: Data Synchronization
```bash
make sync       # 🚀 Run data synchronization (DSBulk)
make test-sync  # 🔍 Verify data count in both clusters
```

### Phase 5: Dual-Write Mode
```bash
make phase-dual # 🚀 Switch to dual-write mode
make test-dual  # 🔍 Test dual-write functionality
```

### Phase 6: Direct Astra Connection
```bash
make phase-astra # 🚀 Direct Astra connection (Phase 5)
make test-astra  # 🔍 Test direct Astra connection
```

### Phase 7: Cleanup
```bash
make cleanup    # 🧹 Remove ZDM proxy
make down       # 🧹 Teardown entire cluster
```

## Prerequisites

- **Kind** (Kubernetes in Docker)
- **kubectl** (Kubernetes CLI) 
- **Podman** or Docker
- **curl** and **jq** for testing
- **DataStax Astra DB** account with:
  - Secure Connect Bundle
  - Application Token

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

# ZDM Configuration (optional)
ZDM_VERSION=v2.3.4
```

## Project Structure

```
├── k8s/
│   ├── cassandra/        # Cassandra StatefulSet
│   ├── data-generator/   # Job to populate demo data  
│   ├── data-sync/        # DSBulk migration job
│   └── zdm-proxy/        # ZDM Proxy deployment
├── python-api/           # FastAPI service
├── Makefile             # Demo workflow commands
├── patch-api-astra.sh   # Phase 5 direct connection script
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

### Manual Testing Commands

```bash
# Test API health
curl -s http://localhost:8080/ | jq .

# List users  
curl -s http://localhost:8080/users?limit=5 | jq .

# Create user
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com","gender":"Other","address":"Test Address"}'

# Check Cassandra data count
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
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

### Debug specific components
```bash
kubectl get pods                    # Check pod status
kubectl logs -l app=cassandra      # Cassandra logs
kubectl logs -l app=zdm-proxy      # ZDM proxy logs  
kubectl logs -l app=python-api     # API logs
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