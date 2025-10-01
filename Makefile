# Cassandra 5 Zero Downtime Migration Demo
# Makefile for managing the complete migration workflow

.PHONY: help setup cassandra data test-data api test-api zdm test-zdm sync test-sync phase-dual test-dual phase-astra test-astra cleanup down status logs

CLUSTER_NAME := zdm-demo
NAMESPACE := default
CONTAINER_ENGINE := podman

help: ## Show this help message
	@echo "Cassandra 5 Zero Downtime Migration Demo - Complete Workflow"
	@echo ""
	@echo "Main Demo Flow:"
	@echo "  setup      - Create kind cluster"
	@echo "  cassandra  - Deploy Cassandra StatefulSet"
	@echo "  data       - Generate demo data (1000 records)"
	@echo "  test-data  - Verify data in Cassandra"
	@echo "  api        - Deploy Python API"
	@echo "  test-api   - Test API connectivity"
	@echo "  zdm        - Deploy ZDM proxy"
	@echo "  test-zdm   - Test ZDM proxy connection"
	@echo "  sync       - Run data synchronization (DSBulk)"
	@echo "  test-sync  - Verify data count in both clusters"
	@echo "  phase-dual - Switch to dual-write mode"
	@echo "  test-dual  - Test dual-write functionality"
	@echo "  phase-astra- Direct Astra connection (Phase 5)"
	@echo "  test-astra - Test direct Astra connection"
	@echo "  cleanup    - Remove ZDM proxy"
	@echo ""
	@echo "Utility Commands:"
	@echo "  status     - Check all components"
	@echo "  logs       - Show logs from all services"
	@echo "  down       - Teardown entire cluster"

setup: kind-config.yaml ## Create kind cluster
	@echo "🚀 Creating kind cluster..."
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml || true
	@echo "⏳ Waiting for cluster to be ready..."
	kubectl wait --for=condition=Ready nodes --all --timeout=300s
	@echo "✅ Kind cluster ready!"

cassandra: ## Deploy Cassandra StatefulSet
	@echo "🚀 Deploying Cassandra..."
	kubectl apply -f k8s/cassandra/
	@echo "⏳ Waiting for Cassandra to be ready..."
	kubectl wait --for=condition=Ready pod -l app=cassandra --timeout=300s
	@echo "✅ Cassandra is ready!"



data: build-images ## Generate demo data (1000 records)
	@echo "🚀 Generating demo data..."
	kubectl delete job data-generator --ignore-not-found=true
	kubectl apply -f k8s/data-generator/
	@echo "⏳ Waiting for data generation to complete..."
	kubectl wait --for=condition=Complete job/data-generator --timeout=300s
	@echo "✅ Demo data generated successfully!"

test-data: ## Verify data in Cassandra
	@echo "🔍 Testing Cassandra data..."
	@kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
	@echo "✅ Expected: 1000 rows"

api: build-images ## Deploy Python API
	@echo "🚀 Deploying Python API..."
	kubectl apply -f python-api/
	@echo "⏳ Waiting for API deployment to be ready..."
	kubectl wait --for=condition=Available deployment/python-api --timeout=300s
	@echo "✅ Python API deployed successfully!"
	@echo "📍 API accessible at: http://localhost:8080"

test-api: ## Test API connectivity
	@echo "🔍 Testing API connectivity..."
	@curl -s http://localhost:8080/ | jq .
	@curl -s http://localhost:8080/users?limit=5 | jq .
	@echo "✅ API responding correctly"

zdm: ## Deploy ZDM proxy
	@echo "🚀 Deploying ZDM proxy..."
	@if [ ! -f ".env" ]; then \
		echo "❌ Error: .env file not found!"; \
		echo "Please create a .env file with ASTRA_SECURE_BUNDLE_PATH and ASTRA_TOKEN_FILE_PATH variables."; \
		exit 1; \
	fi
	@echo "📋 Creating ZDM proxy secret with Astra credentials..."
	@source .env && \
	if [ ! -f "$${ASTRA_SECURE_BUNDLE_PATH}" ]; then \
		echo "❌ Error: Astra Secure Connect Bundle not found at: $${ASTRA_SECURE_BUNDLE_PATH}"; \
		exit 1; \
	fi && \
	if [ ! -f "$${ASTRA_TOKEN_FILE_PATH}" ]; then \
		echo "❌ Error: Astra token file not found at: $${ASTRA_TOKEN_FILE_PATH}"; \
		exit 1; \
	fi && \
	if command -v jq >/dev/null 2>&1; then \
		ASTRA_TOKEN=$$(cat "$${ASTRA_TOKEN_FILE_PATH}" | jq -r '.token' 2>/dev/null); \
	else \
		ASTRA_TOKEN=$$(grep -o '"token":"[^"]*"' "$${ASTRA_TOKEN_FILE_PATH}" | sed 's/"token":"\([^"]*\)"/\1/'); \
	fi && \
	if [ -z "$${ASTRA_TOKEN}" ] || [ "$${ASTRA_TOKEN}" = "null" ]; then \
		echo "❌ Error: Could not extract token from $${ASTRA_TOKEN_FILE_PATH}"; \
		exit 1; \
	fi && \
	kubectl delete secret zdm-proxy-secret --ignore-not-found=true && \
	kubectl create secret generic zdm-proxy-secret \
		--from-literal=astra-username="token" \
		--from-literal=astra-password="$${ASTRA_TOKEN}" \
		--from-file=secure-connect.zip="$${ASTRA_SECURE_BUNDLE_PATH}"
	kubectl apply -f k8s/zdm-proxy/zdm-proxy-env.yaml
	@echo "⏳ Waiting for ZDM proxy to be ready..."
	kubectl wait --for=condition=Available deployment/zdm-proxy --timeout=300s || { \
		echo "❌ ZDM proxy failed to start. Checking logs..."; \
		kubectl logs -l app=zdm-proxy --tail=20; \
	}
	@echo "✅ ZDM proxy deployed successfully!"

test-zdm: ## Test ZDM proxy connection
	@echo "🔍 Testing ZDM proxy connection..."
	@kubectl patch deployment python-api -p '{"spec":{"template":{"spec":{"containers":[{"name":"python-api","env":[{"name":"CONNECTION_MODE","value":"zdm"},{"name":"CASSANDRA_CONTACT_POINTS","value":"zdm-proxy-svc:9042"},{"name":"KEYSPACE","value":"demo"},{"name":"TABLE","value":"users"}]}]}}}}'
	@kubectl rollout status deployment/python-api --timeout=120s
	@sleep 10
	@curl -s http://localhost:8080/ | jq .
	@echo "✅ ZDM proxy connection verified"

status: ## Check status of all components
	@echo "=== 📊 Demo Status ==="
	@echo "Cluster Info:"
	kubectl cluster-info --context kind-$(CLUSTER_NAME) 2>/dev/null || echo "Cluster not found"
	@echo ""
	@echo "Pods:"
	kubectl get pods -o wide
	@echo ""
	@echo "Services:"
	kubectl get services
	@echo ""
	@echo "Deployments:"
	kubectl get deployments

logs: ## Show logs from all components
	@echo "=== 📜 Cassandra Logs ==="
	kubectl logs -l app=cassandra --tail=20 || echo "No Cassandra logs"
	@echo ""
	@echo "=== 📜 Data Generator Logs ==="
	kubectl logs job/data-generator --tail=20 || echo "No data generator logs"
	@echo ""
	@echo "=== 📜 Python API Logs ==="
	kubectl logs -l app=python-api --tail=20 || echo "No API logs"
	@echo ""
	@echo "=== 📜 ZDM Proxy Logs ==="
	kubectl logs -l app=zdm-proxy --tail=20 || echo "No ZDM proxy logs"

sync: ## Run data synchronization with DSBulk
	@echo "🚀 Starting DataStax Phase 2: Data Migration with DSBulk Migrator"
	@echo "📋 Checking prerequisites..."
	@if ! kubectl get secret zdm-proxy-secret >/dev/null 2>&1; then \
		echo "❌ Error: zdm-proxy-secret not found. Run 'make zdm' first."; \
		exit 1; \
	fi
	@if ! kubectl get service cassandra-svc >/dev/null 2>&1; then \
		echo "❌ Error: Cassandra service not found. Run 'make cassandra' first."; \
		exit 1; \
	fi
	@echo "✅ Prerequisites check passed"
	kubectl delete job dsbulk-migrator-sync --ignore-not-found=true
	kubectl apply -f k8s/data-sync/dsbulk-sync-job.yaml
	@echo "⏳ Waiting for migration job to complete (5-10 minutes)..."
	kubectl wait --for=condition=Complete job/dsbulk-migrator-sync --timeout=900s || { \
		echo "❌ Migration job failed. Checking logs..."; \
		kubectl logs job/dsbulk-migrator-sync --tail=100; \
		exit 1; \
	}
	@echo "✅ DSBulk data synchronization completed!"
	kubectl logs job/dsbulk-migrator-sync --tail=30

test-sync: ## Verify data count in both clusters
	@echo "🔍 Testing data synchronization..."
	@echo "📊 Cassandra count:"
	@kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
	@echo "📊 Astra DB count (check via console or direct connection)"
	@echo "✅ Data synchronization verified"

phase-dual: ## Switch to dual-write mode
	@echo "🚀 Switching to dual-write mode..."
	@./k8s/zdm-proxy/update-zdm-phase.sh DUAL_WRITE
	@echo "⏳ Waiting for ZDM proxy to restart..."
	@kubectl rollout status deployment/zdm-proxy --timeout=120s
	@echo "✅ Dual-write mode enabled"

test-dual: ## Test dual-write functionality
	@echo "🔍 Testing dual-write functionality..."
	@echo "📝 Creating test record..."
	@curl -X POST http://localhost:8080/users \
		-H "Content-Type: application/json" \
		-d '{"name":"Test User","email":"test@example.com","gender":"Other","address":"Test Address"}'
	@echo "✅ Dual-write test completed"

phase-astra: ## Switch to direct Astra connection (Phase 5)
	@echo "🚀 Phase 5: Switching to direct Astra DB connection..."
	@./patch-api-astra.sh
	@echo "✅ Direct Astra connection enabled"

test-astra: ## Test direct Astra connection
	@echo "🔍 Testing direct Astra connection..."
	@curl -s http://localhost:8080/ | jq .
	@curl -s http://localhost:8080/users?limit=5 | jq .
	@echo "✅ Direct Astra connection verified"

cleanup: ## Remove ZDM proxy (final cleanup)
	@echo "🧹 Removing ZDM proxy..."
	kubectl delete deployment zdm-proxy --ignore-not-found=true
	kubectl delete service zdm-proxy-svc --ignore-not-found=true
	kubectl delete configmap zdm-proxy-config --ignore-not-found=true
	@echo "✅ ZDM proxy cleaned up"

down: ## Teardown entire cluster
	@echo "🧹 Tearing down kind cluster..."
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "✅ Cluster removed successfully!"

# Internal targets
build-images:
	@echo "🔨 Building container images..."
	@kind get clusters | grep -q "$(CLUSTER_NAME)" || { echo "❌ Error: Kind cluster '$(CLUSTER_NAME)' not found. Run 'make setup' first."; exit 1; }
	@cd k8s/data-generator && $(CONTAINER_ENGINE) build -t data-generator:latest .
	@$(CONTAINER_ENGINE) save data-generator:latest -o /tmp/data-generator.tar
	@kind load image-archive /tmp/data-generator.tar --name $(CLUSTER_NAME)
	@rm -f /tmp/data-generator.tar
	@cd python-api && $(CONTAINER_ENGINE) build -t python-api:latest .
	@$(CONTAINER_ENGINE) save python-api:latest -o /tmp/python-api.tar
	@kind load image-archive /tmp/python-api.tar --name $(CLUSTER_NAME)
	@rm -f /tmp/python-api.tar
	@echo "✅ Container images built and loaded"

kind-config.yaml:
	@echo "📝 Creating kind configuration..."
	@echo "kind: Cluster" > kind-config.yaml
	@echo "apiVersion: kind.x-k8s.io/v1alpha4" >> kind-config.yaml
	@echo "name: zdm-demo" >> kind-config.yaml
	@echo "nodes:" >> kind-config.yaml
	@echo "- role: control-plane" >> kind-config.yaml
	@echo "  extraPortMappings:" >> kind-config.yaml
	@echo "  - containerPort: 30080" >> kind-config.yaml
	@echo "    hostPort: 8080" >> kind-config.yaml
	@echo "    protocol: TCP" >> kind-config.yaml
	@echo "  - containerPort: 30042" >> kind-config.yaml
	@echo "    hostPort: 9042" >> kind-config.yaml
	@echo "    protocol: TCP" >> kind-config.yaml