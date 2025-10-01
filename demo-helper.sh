#!/bin/bash
# Demo Helper Script - ZDM Migration Phases

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to patch API to use ZDM proxy
patch_api_to_zdm() {
    echo_step "Patching API to use ZDM proxy"
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
    kubectl rollout status deployment/python-api --timeout=60s
    echo_success "API now routes through ZDM proxy"
}

# Function to configure ZDM for dual-write
configure_zdm_dual_write() {
    echo_step "Configuring ZDM for dual-write mode"
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
    kubectl rollout status deployment/zdm-proxy --timeout=60s
    echo_success "ZDM proxy now in dual-write mode"
}

# Function to configure ZDM for target-only
configure_zdm_target_only() {
    echo_step "Configuring ZDM for target-only mode"
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
    kubectl rollout status deployment/zdm-proxy --timeout=60s
    echo_success "ZDM proxy now in target-only mode"
}

# Function to test API connectivity
test_api() {
    echo_step "Testing API connectivity"
    local response=$(curl -s http://localhost:8080/ || echo "ERROR")
    if [[ "$response" == "ERROR" ]]; then
        echo_error "API not reachable at localhost:8080"
        return 1
    fi
    echo "$response" | jq .
    echo_success "API is responsive"
}

# Function to create test record
create_test_record() {
    local name="$1"
    local email="$2"
    echo_step "Creating test record: $name"
    curl -s -X POST http://localhost:8080/users \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$name\", \"email\": \"$email\", \"gender\": \"Other\", \"address\": \"Demo Test Record\"}" | jq .
    echo_success "Test record created"
}

# Function to verify record in Cassandra
verify_cassandra_record() {
    local email="$1"
    echo_step "Verifying record exists in Cassandra"
    local count=$(kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users WHERE email = '$email';" 2>/dev/null | grep -E '^\s*[0-9]+' | xargs || echo "0")
    if [[ "$count" -gt 0 ]]; then
        echo_success "Record found in Cassandra (count: $count)"
    else
        echo_warning "Record not found in Cassandra"
    fi
}

# Main demo workflow
case "${1:-help}" in
    "patch-api-zdm")
        patch_api_to_zdm
        ;;
    "zdm-dual-write")
        configure_zdm_dual_write
        ;;
    "zdm-target-only")
        configure_zdm_target_only
        ;;
    "test-api")
        test_api
        ;;
    "create-test")
        create_test_record "${2:-Demo User}" "${3:-demo-$(date +%s)@example.com}"
        ;;
    "verify-cassandra")
        verify_cassandra_record "${2:-demo@example.com}"
        ;;
    "help"|*)
        echo "ZDM Demo Helper Script"
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  patch-api-zdm      - Patch API to use ZDM proxy"
        echo "  zdm-dual-write     - Configure ZDM for dual-write mode"
        echo "  zdm-target-only    - Configure ZDM for target-only mode"
        echo "  test-api           - Test API connectivity and status"
        echo "  create-test [name] [email] - Create test record"
        echo "  verify-cassandra [email]   - Verify record exists in Cassandra"
        echo "  help               - Show this help"
        ;;
esac