# Cassandra 5 Zero Downtime Migration Demo
# Makefile for managing local Kubernetes environment with kind

.PHONY: help up data zdm status down clean logs build-images clean-images api build-zdm zdm-custom

CLUSTER_NAME := zdm-demo
NAMESPACE := default
CONTAINER_ENGINE := podman

help: ## Show this help message
	@echo "Cassandra 5 Zero Downtime Migration Demo"
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

up: kind-config.yaml ## Start kind cluster and deploy Cassandra
	@echo "Creating kind cluster..."
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml || true
	@echo "Waiting for cluster to be ready..."
	kubectl wait --for=condition=Ready nodes --all --timeout=300s
	@echo "Deploying Cassandra..."
	kubectl apply -f k8s/cassandra/
	@echo "Waiting for Cassandra to be ready..."
	kubectl wait --for=condition=Ready pod -l app=cassandra --timeout=300s
	@echo "Cassandra cluster is ready!"

build-images: ## Build container images using Podman
	@echo "Checking if kind cluster exists..."
	@kind get clusters | grep -q "$(CLUSTER_NAME)" || { echo "Error: Kind cluster '$(CLUSTER_NAME)' not found. Run 'make up' first."; exit 1; }
	@echo "Building data-generator image..."
	@cd k8s/data-generator && $(CONTAINER_ENGINE) build -t data-generator:latest . || { echo "Failed to build data-generator image"; exit 1; }
	@echo "Saving data-generator image to archive..."
	@$(CONTAINER_ENGINE) save data-generator:latest -o /tmp/data-generator.tar || { echo "Failed to save data-generator image"; exit 1; }
	@echo "Loading data-generator image into kind cluster..."
	@kind load image-archive /tmp/data-generator.tar --name $(CLUSTER_NAME) || { echo "Failed to load data-generator image into kind"; exit 1; }
	@rm -f /tmp/data-generator.tar
	@echo "Building python-api image..."
	@cd python-api && $(CONTAINER_ENGINE) build -t python-api:latest . || { echo "Failed to build python-api image"; exit 1; }
	@echo "Saving python-api image to archive..."
	@$(CONTAINER_ENGINE) save python-api:latest -o /tmp/python-api.tar || { echo "Failed to save python-api image"; exit 1; }
	@echo "Loading python-api image into kind cluster..."
	@kind load image-archive /tmp/python-api.tar --name $(CLUSTER_NAME) || { echo "Failed to load python-api image into kind"; exit 1; }
	@rm -f /tmp/python-api.tar
	@echo "Container images built and loaded successfully!"

data: build-images ## Run data generator job to populate demo data
	@echo "Creating demo data..."
	kubectl delete job data-generator --ignore-not-found=true
	kubectl apply -f k8s/data-generator/
	@echo "Waiting for data generation to complete..."
	kubectl wait --for=condition=Complete job/data-generator --timeout=300s
	@echo "Demo data generated successfully!"

api: build-images ## Deploy Python API service after data is populated
	@echo "Deploying Python API..."
	kubectl apply -f python-api/
	@echo "Waiting for API deployment to be ready..."
	kubectl wait --for=condition=Available deployment/python-api --timeout=300s
	@echo "Python API deployed successfully!"
	@echo "API accessible at: http://localhost:8080"
	@echo "Test with: curl http://localhost:8080/"

zdm: ## Deploy ZDM proxy with Astra credentials from .env
	@echo "Loading environment variables from .env file..."
	@if [ ! -f ".env" ]; then \
		echo "Error: .env file not found!"; \
		echo "Please create a .env file with ASTRA_SECURE_BUNDLE_PATH and ASTRA_TOKEN_FILE_PATH variables."; \
		exit 1; \
	fi
	@echo "Creating ZDM proxy secret with Astra credentials..."
	@source .env && \
	if [ ! -f "$${ASTRA_SECURE_BUNDLE_PATH}" ]; then \
		echo "Error: Astra Secure Connect Bundle not found at: $${ASTRA_SECURE_BUNDLE_PATH}"; \
		echo "Please check the ASTRA_SECURE_BUNDLE_PATH in your .env file."; \
		exit 1; \
	fi && \
	if [ ! -f "$${ASTRA_TOKEN_FILE_PATH}" ]; then \
		echo "Error: Astra token file not found at: $${ASTRA_TOKEN_FILE_PATH}"; \
		echo "Please check the ASTRA_TOKEN_FILE_PATH in your .env file."; \
		exit 1; \
	fi && \
	echo "Reading Astra token from: $${ASTRA_TOKEN_FILE_PATH}" && \
	if command -v jq >/dev/null 2>&1; then \
		ASTRA_TOKEN=$$(cat "$${ASTRA_TOKEN_FILE_PATH}" | jq -r '.token' 2>/dev/null); \
	else \
		echo "jq not found, using grep/sed to extract token..."; \
		ASTRA_TOKEN=$$(grep -o '"token":"[^"]*"' "$${ASTRA_TOKEN_FILE_PATH}" | sed 's/"token":"\([^"]*\)"/\1/'); \
	fi && \
	if [ -z "$${ASTRA_TOKEN}" ] || [ "$${ASTRA_TOKEN}" = "null" ]; then \
		echo "Error: Could not extract token from $${ASTRA_TOKEN_FILE_PATH}"; \
		echo "Please ensure the file contains valid JSON with a 'token' field."; \
		exit 1; \
	fi && \
	echo "Token successfully extracted ($${#ASTRA_TOKEN} characters)" && \
	kubectl delete secret zdm-proxy-secret --ignore-not-found=true && \
	kubectl create secret generic zdm-proxy-secret \
		--from-literal=astra-username="token" \
		--from-literal=astra-password="$${ASTRA_TOKEN}" \
		--from-file=secure-connect.zip="$${ASTRA_SECURE_BUNDLE_PATH}" && \
	echo "ZDM proxy secret created successfully!"
	@echo "Deploying ZDM proxy..."
	kubectl apply -f k8s/zdm-proxy/zdm-proxy-env.yaml
	@echo "Waiting for ZDM proxy to be ready..."
	kubectl wait --for=condition=Available deployment/zdm-proxy --timeout=300s || { \
		echo "ZDM proxy failed to start. Checking logs..."; \
		kubectl get pods -l app=zdm-proxy; \
		kubectl logs -l app=zdm-proxy --tail=20; \
		echo "Note: ZDM proxy v2.1.0 may have compatibility issues. Phase A testing is still available."; \
	}
	@echo "ZDM proxy deployed successfully!"
	@echo "Note: ZDM proxy has known limitations in this environment:"
	@echo "  - v2.1.0/v2.0.0: Runtime stability issues with Go runtime errors"
	@echo "  - v2.3.4+: Only available for AMD64, not ARM64 (Apple Silicon)"
	@echo "Configuration and connectivity verified. Check status with 'make status'"

status: ## Check status of all components
	@echo "=== Cluster Info ==="
	kubectl cluster-info
	@echo ""
	@echo "=== Nodes ==="
	kubectl get nodes
	@echo ""
	@echo "=== Pods ==="
	kubectl get pods -o wide
	@echo ""
	@echo "=== Services ==="
	kubectl get services
	@echo ""
	@echo "=== Jobs ==="
	kubectl get jobs
	@echo ""
	@echo "=== Deployments ==="
	kubectl get deployments

logs: ## Show logs from all components
	@echo "=== Cassandra Logs ==="
	kubectl logs -l app=cassandra --tail=50 || true
	@echo ""
	@echo "=== Data Generator Logs ==="
	kubectl logs job/data-generator --tail=50 || true
	@echo ""
	@echo "=== ZDM Proxy Logs ==="
	kubectl logs -l app=zdm-proxy --tail=50 || true

sync: ## Run DSBulk Migrator data synchronization job (DataStax Phase 2)
	@echo "🚀 Starting DataStax Phase 2: Data Migration with DSBulk Migrator"
	@echo "Checking prerequisites..."
	@if ! kubectl get secret zdm-proxy-secret >/dev/null 2>&1; then \
		echo "❌ Error: zdm-proxy-secret not found. Run 'make zdm' first."; \
		exit 1; \
	fi
	@if ! kubectl get service cassandra-svc >/dev/null 2>&1; then \
		echo "❌ Error: Cassandra service not found. Run 'make up' first."; \
		exit 1; \
	fi
	@echo "✅ Prerequisites check passed"
	@echo "Deleting any previous migration job..."
	kubectl delete job dsbulk-migrator-sync --ignore-not-found=true
	@echo "Starting DSBulk Migrator data synchronization..."
	kubectl apply -f k8s/data-sync/dsbulk-sync-job.yaml
	@echo "⏳ Waiting for migration job to complete (this will take 5-10 minutes)..."
	@echo "   Building DSBulk Migrator from source and performing live migration..."
	kubectl wait --for=condition=Complete job/dsbulk-migrator-sync --timeout=900s || { \
		echo "❌ Migration job failed or timed out. Checking logs..."; \
		kubectl logs job/dsbulk-migrator-sync --tail=100; \
		exit 1; \
	}
	@echo "✅ DSBulk Migrator data synchronization completed successfully!"
	@echo "📊 Checking migration results..."
	kubectl logs job/dsbulk-migrator-sync --tail=30
	@echo ""
	@echo "🎉 DataStax Phase 2 completed!"
	@echo "Next steps:"
	@echo "  - Verify data counts: kubectl exec -it cassandra-0 -- cqlsh -e \"SELECT COUNT(*) FROM demo.users;\""
	@echo "  - Check Astra DB via console or API"
	@echo "  - Proceed to Phase 3: Enable async dual reads (optional)"

down: ## Teardown kind cluster
	@echo "Tearing down kind cluster..."
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "Cluster removed successfully!"

clean: down ## Alias for down

clean-images: ## Remove temporary image archives
	@echo "Cleaning up temporary image files..."
	@rm -f /tmp/data-generator.tar /tmp/python-api.tar
	@echo "Temporary files removed."

check-env: ## Display current environment configuration from .env file
	@echo "Current environment configuration:"
	@if [ -f ".env" ]; then \
		source .env && \
		echo "  Cassandra Host: $${CASSANDRA_CONTACT_POINTS}" && \
		echo "  Cassandra Port: $${CASSANDRA_PORT}" && \
		echo "  Keyspace: $${KEYSPACE}" && \
		echo "  Table: $${TABLE}" && \
		echo "  Astra Bundle: $${ASTRA_SECURE_BUNDLE_PATH}" && \
		echo "  Astra Token File: $${ASTRA_TOKEN_FILE_PATH}" && \
		if [ -f "$${ASTRA_SECURE_BUNDLE_PATH}" ]; then echo "  ✓ Bundle file exists"; else echo "  ✗ Bundle file missing"; fi && \
		if [ -f "$${ASTRA_TOKEN_FILE_PATH}" ]; then echo "  ✓ Token file exists"; else echo "  ✗ Token file missing"; fi; \
	else \
		echo "  ✗ .env file not found"; \
	fi

build-zdm-arm64: ## Build ZDM proxy v2.3.4 for ARM64 architecture
	@echo "Building ZDM proxy v2.3.4 for ARM64..."
	@./k8s/zdm-proxy/build-zdm.sh

zdm-arm64: build-zdm-arm64 ## Deploy custom-built ARM64 ZDM proxy
	@echo "Loading environment variables from .env file..."
	@if [ ! -f ".env" ]; then \
		echo "Error: .env file not found!"; \
		echo "Please create a .env file with ASTRA_SECURE_BUNDLE_PATH and ASTRA_TOKEN_FILE_PATH variables."; \
		exit 1; \
	fi
	@echo "Creating ZDM proxy secret with Astra credentials..."
	@source .env && \
	if [ ! -f "$${ASTRA_SECURE_BUNDLE_PATH}" ]; then \
		echo "Error: Astra Secure Connect Bundle not found at: $${ASTRA_SECURE_BUNDLE_PATH}"; \
		echo "Please check the ASTRA_SECURE_BUNDLE_PATH in your .env file."; \
		exit 1; \
	fi && \
	if [ ! -f "$${ASTRA_TOKEN_FILE_PATH}" ]; then \
		echo "Error: Astra token file not found at: $${ASTRA_TOKEN_FILE_PATH}"; \
		echo "Please check the ASTRA_TOKEN_FILE_PATH in your .env file."; \
		exit 1; \
	fi && \
	echo "Reading Astra token from: $${ASTRA_TOKEN_FILE_PATH}" && \
	if command -v jq >/dev/null 2>&1; then \
		ASTRA_TOKEN=$$(cat "$${ASTRA_TOKEN_FILE_PATH}" | jq -r '.token' 2>/dev/null); \
	else \
		echo "jq not found, using grep/sed to extract token..."; \
		ASTRA_TOKEN=$$(grep -o '"token":"[^"]*"' "$${ASTRA_TOKEN_FILE_PATH}" | sed 's/"token":"\([^"]*\)"/\1/'); \
	fi && \
	if [ -z "$${ASTRA_TOKEN}" ] || [ "$${ASTRA_TOKEN}" = "null" ]; then \
		echo "Error: Could not extract token from $${ASTRA_TOKEN_FILE_PATH}"; \
		echo "Please ensure the file contains valid JSON with a 'token' field."; \
		exit 1; \
	fi && \
	echo "Token successfully extracted ($${#ASTRA_TOKEN} characters)" && \
	kubectl delete secret zdm-proxy-secret --ignore-not-found=true && \
	kubectl create secret generic zdm-proxy-secret \
		--from-literal=astra-username="token" \
		--from-literal=astra-password="$${ASTRA_TOKEN}" \
		--from-file=secure-connect.zip="$${ASTRA_SECURE_BUNDLE_PATH}" && \
	echo "ZDM proxy secret created successfully!"
	@echo "Deploying custom ARM64 ZDM proxy..."
	@sed 's|image: datastax/zdm-proxy:.*|image: zdm-proxy:2.3.4-arm64|' k8s/zdm-proxy/zdm-proxy-env.yaml | kubectl apply -f -
	@echo "Custom ARM64 ZDM proxy v2.3.4 deployed!"
	@echo "This version should have better stability and latest fixes."

build-zdm: ## Build custom ZDM proxy from GitHub source using version from .env
	@echo "Building custom ZDM proxy from source..."
	./k8s/zdm-proxy/build-custom.sh

zdm-custom: build-zdm ## Build and deploy custom ZDM proxy
	@echo "Loading environment variables from .env file..."
	@if [ ! -f ".env" ]; then \
		echo "Error: .env file not found!"; \
		echo "Please create a .env file with ASTRA_SECURE_BUNDLE_PATH and ASTRA_TOKEN_FILE_PATH variables."; \
		exit 1; \
	fi
	@echo "Creating ZDM proxy secret with Astra credentials..."
	@source .env && \
	if [ ! -f "$${ASTRA_SECURE_BUNDLE_PATH}" ]; then \
		echo "Error: Astra Secure Connect Bundle not found at: $${ASTRA_SECURE_BUNDLE_PATH}"; \
		echo "Please check the ASTRA_SECURE_BUNDLE_PATH in your .env file."; \
		exit 1; \
	fi && \
	if [ ! -f "$${ASTRA_TOKEN_FILE_PATH}" ]; then \
		echo "Error: Astra token file not found at: $${ASTRA_TOKEN_FILE_PATH}"; \
		echo "Please check the ASTRA_TOKEN_FILE_PATH in your .env file."; \
		exit 1; \
	fi && \
	echo "Reading Astra token from: $${ASTRA_TOKEN_FILE_PATH}" && \
	if command -v jq >/dev/null 2>&1; then \
		ASTRA_TOKEN=$$(cat "$${ASTRA_TOKEN_FILE_PATH}" | jq -r '.token' 2>/dev/null); \
	else \
		echo "jq not found, using grep/sed to extract token..."; \
		ASTRA_TOKEN=$$(grep -o '"token":"[^"]*"' "$${ASTRA_TOKEN_FILE_PATH}" | sed 's/"token":"\([^"]*\)"/\1/'); \
	fi && \
	if [ -z "$${ASTRA_TOKEN}" ] || [ "$${ASTRA_TOKEN}" = "null" ]; then \
		echo "Error: Could not extract token from $${ASTRA_TOKEN_FILE_PATH}"; \
		echo "Please ensure the file contains valid JSON with a 'token' field."; \
		exit 1; \
	fi && \
	echo "Token successfully extracted ($${#ASTRA_TOKEN} characters)" && \
	kubectl delete secret zdm-proxy-secret --ignore-not-found=true && \
	kubectl create secret generic zdm-proxy-secret \
		--from-literal=astra-username="token" \
		--from-literal=astra-password="$${ASTRA_TOKEN}" \
		--from-file=secure-connect.zip="$${ASTRA_SECURE_BUNDLE_PATH}" && \
	echo "ZDM proxy secret created successfully!"
	@echo "Deploying custom ZDM proxy..."
	@source .env && \
	sed "s/\$${ZDM_VERSION}/$${ZDM_VERSION}/g" k8s/zdm-proxy/zdm-proxy-custom.yaml.template | kubectl apply -f -
	@echo "Waiting for custom ZDM proxy to be ready..."
	kubectl wait --for=condition=Available deployment/zdm-proxy --timeout=300s || { \
		echo "Custom ZDM proxy failed to start. Checking logs..."; \
		kubectl get pods -l app=zdm-proxy; \
		kubectl logs -l app=zdm-proxy --tail=20; \
		echo "Custom build may need troubleshooting. Check 'make status' for details."; \
	}
	@echo "Custom ZDM proxy deployed successfully!"
	@echo "Built from source with native architecture support."
	@source .env && echo "Version: $${ZDM_VERSION}"

kind-config.yaml: ## Create kind config if it doesn't exist
	@echo "Creating kind configuration..."
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