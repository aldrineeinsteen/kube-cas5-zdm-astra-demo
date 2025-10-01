# Cassandra 5 Zero Downtime Migration Demo
# Simplified Makefile for core deployment commands only

.PHONY: help setup cassandra data api zdm build-zdm build-images down

CLUSTER_NAME := zdm-demo
NAMESPACE := default
CONTAINER_ENGINE := podman

help: ## Show this help message
	@echo "Cassandra 5 Zero Downtime Migration Demo - Core Commands"
	@echo ""
	@echo "Core Deployment Flow:"
	@echo "  setup      - Create kind cluster"
	@echo "  cassandra  - Deploy Cassandra StatefulSet"
	@echo "  data       - Generate demo data (1000 records)"
	@echo "  api        - Deploy Python API (connects to cassandra-svc by default)"
	@echo "  zdm        - Build and deploy ZDM proxy (ARM64 compatible)"
	@echo ""
	@echo "Utility Commands:"
	@echo "  down       - Teardown entire cluster"
	@echo ""
	@echo "For testing, patching, and phase management commands, see README.md"

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
	kubectl apply -f k8s/data-generator/
	@echo "⏳ Waiting for data generation to complete..."
	kubectl wait --for=condition=complete job/data-generator --timeout=300s
	@echo "✅ Demo data generated successfully!"

api: build-images ## Deploy Python API (connects to cassandra-svc by default)
	@echo "🚀 Deploying Python API..."
	kubectl apply -f python-api/
	@echo "⏳ Waiting for API deployment to be ready..."
	kubectl wait --for=condition=Available deployment/python-api --timeout=300s
	@echo "✅ Python API deployed successfully!"
	@echo "📍 API accessible at: http://localhost:8080"

build-zdm: ## Build ZDM proxy ARM64 image and load into kind
	@echo "🏗️  Building ZDM proxy ARM64 image..."
	@./scripts/build-zdm-arm64.sh

zdm: build-zdm ## Build and deploy ZDM proxy (ARM64 compatible)
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
	@echo "📋 Deploying ZDM proxy with version $${ZDM_VERSION:-v2.3.4}..."
	@source .env && \
	ZDM_VERSION=$${ZDM_VERSION:-v2.3.4} envsubst < k8s/zdm-proxy/zdm-proxy-env.yaml | kubectl apply -f -
	@echo "⏳ Waiting for ZDM proxy to be ready..."
	kubectl wait --for=condition=Available deployment/zdm-proxy --timeout=300s || { \
		echo "❌ ZDM proxy failed to start. Checking logs..."; \
		kubectl logs -l app=zdm-proxy --tail=20; \
	}
	@echo "✅ ZDM proxy deployed successfully!"

down: ## Teardown entire cluster
	@echo "🧹 Tearing down kind cluster..."
	kind delete cluster --name $(CLUSTER_NAME) || true
	@echo "✅ Cluster deleted!"

build-images: ## Build container images and load into kind
	@echo "🔨 Building container images..."
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