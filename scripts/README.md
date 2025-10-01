# Scripts Directory

This directory contains all utility scripts for the ZDM demo project.

## ZDM Management Scripts

### `build-zdm-arm64.sh`
**Purpose**: Builds a local ZDM proxy image with ARM64 binary and loads it into the kind cluster.

**Usage**:
```bash
./scripts/build-zdm-arm64.sh
```

**Features**:
- Downloads official ZDM proxy ARM64 binary from GitHub releases
- Builds Docker image with Podman
- Loads image into kind cluster for local use
- Resolves ARM64/Apple Silicon compatibility issues

**Environment Variables**:
- `ZDM_VERSION`: ZDM proxy version to build (default: v2.3.4)
- `KIND_CLUSTER_NAME`: Kind cluster name (default: zdm-demo)

### `update-zdm-phase.sh`
**Purpose**: Manages ZDM migration phases by updating deployment configuration.

**Usage**:
```bash
./scripts/update-zdm-phase.sh [A|B|C] [namespace]
```

**Parameters**:
- `A`: Direct writes to source Cassandra only
- `B`: Dual writes to both source and Astra
- `C`: Cutover - all traffic to Astra
- `namespace`: Kubernetes namespace (default: default)

**Make Targets**:
```bash
make phase-a  # Phase A
make phase-b  # Phase B  
make phase-c  # Phase C
```

## Demo & Deployment Scripts

### `demo-helper.sh`
**Purpose**: General demo helper utilities and shortcuts.

**Usage**:
```bash
./scripts/demo-helper.sh [command]
```

### `patch-api-astra.sh`
**Purpose**: Patches the Python API to connect directly to Astra DB (Phase 5).

**Usage**:
```bash
./scripts/patch-api-astra.sh
```

**Features**:
- Updates API deployment to use direct Astra connection
- Sets CONNECTION_MODE=astra environment variable
- Used in Phase 5 of migration workflow

## Astra DB Setup Scripts

### `setup_astra_schema.py`
**Purpose**: Sets up the initial schema in Astra DB.

**Usage**:
```bash
cd scripts && python setup_astra_schema.py
```

**Requirements**:
- Astra DB credentials
- Python cassandra-driver

### `setup_astra_table.py`
**Purpose**: Creates the demo.users table in Astra DB.

**Usage**:
```bash
cd scripts && python setup_astra_table.py
```

### `validate_astra_connection.py`
**Purpose**: Validates connection to Astra DB with credentials.

**Usage**:
```bash
cd scripts && python validate_astra_connection.py
```

**Features**:
- Tests Secure Connect Bundle
- Validates token authentication
- Checks connectivity and permissions

## Testing & Validation Scripts

### `simple_astra_test.py`
**Purpose**: Simple test script for Astra DB operations.

**Usage**:
```bash
cd scripts && python simple_astra_test.py
```

### `test_astra_python39.py`
**Purpose**: Python 3.9 compatibility test for Astra DB.

**Usage**:
```bash
cd scripts && python test_astra_python39.py
```

### `sync-data.py`
**Purpose**: Manual data synchronization between Cassandra and Astra DB.

**Usage**:
```bash
cd scripts && python sync-data.py
```

**Features**:
- Reads data from source Cassandra
- Writes data to target Astra DB
- Alternative to DSBulk migration

## Script Organization

### Core ZDM Scripts
- `build-zdm-arm64.sh` - ARM64 ZDM proxy building
- `update-zdm-phase.sh` - Phase management

### Demo Workflow Scripts  
- `demo-helper.sh` - General demo utilities
- `patch-api-astra.sh` - API connection switching

### Astra DB Management
- `setup_astra_schema.py` - Schema setup
- `setup_astra_table.py` - Table creation
- `validate_astra_connection.py` - Connection validation

### Testing & Sync
- `simple_astra_test.py` - Basic testing
- `test_astra_python39.py` - Python 3.9 compatibility
- `sync-data.py` - Manual data sync

## Usage Notes

- All Python scripts should be run from the `scripts/` directory
- Shell scripts can be run from project root using `./scripts/script-name.sh`
- Make sure to set proper environment variables before running Astra scripts
- Refer to main README.md for complete workflow integration