# Cassandra 5 Zero Downtime Migration Demo

This project demonstrates migrating from Apache Cassandra 5 to DataStax Astra DB using Zero Downtime Migrator (ZDM) on Kubernetes.

## Project Structure

- `k8s/cassandra/` - Cassandra 5 StatefulSet (demo storage only)
- `k8s/zdm-proxy/` - ZDM Proxy deployment with ConfigMap/Secret
- `k8s/data-generator/` - Job to populate demo data
- `python-api/` - FastAPI service for data operations
- `Makefile` - Main build and deployment commands

## Migration Workflow

**Phase Configuration managed via ZDM proxy deployment updates:**
- **Phase A**: Direct writes to source Cassandra only
- **Phase B**: Dual writes through ZDM proxy to both Cassandra and Astra
- **Phase C**: Cutover - all traffic routed to Astra DB

## Essential Commands

```bash
make up       # Start kind cluster and Cassandra
make data     # Generate demo data
make zdm      # Deploy ZDM proxy
make status   # Check all components
make down     # Clean teardown
```

## ZDM Proxy Configuration

**ConfigMap Pattern:**
- Source cluster: `cassandra-svc:9042` (in-cluster service)
- Target: Astra DB via Secure Connect Bundle
- Phase switching via environment variables

**Common Issues:**
- Proxy fails to start: Check Astra credentials in Secret
- Connection timeouts: Verify Cassandra service is ready
- Phase switching: Restart proxy deployment after config changes

## Development Notes

- Demo uses `emptyDir` storage (not persistent)
- Data schema: `UUID, name, email, gender, address`
- All secrets managed via Kubernetes Secret objects
- Use `.env.example` template for local configuration
- British English in all documentation
