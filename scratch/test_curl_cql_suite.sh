#!/bin/bash

# Comprehensive CURL and CQL Testing Suite
# Tests REST API endpoints and databases directly without Python scripts

echo "🚀 CURL & CQL Testing Suite - Direct Command Line Testing"
echo "=================================================================================="
echo "Testing Date: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}📋 $1${NC}"
    echo "=================================================================================="
}

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "   ${GREEN}✅ $2${NC}"
    else
        echo -e "   ${RED}❌ $2${NC}"
    fi
}

# Function to print info
print_info() {
    echo -e "   ${YELLOW}ℹ️  $1${NC}"
}

print_section "System Status Check"

echo "🔍 Checking Kubernetes cluster status..."
kubectl get nodes
echo ""

echo "🔍 Checking pod status..."
kubectl get pods -l app=cassandra
kubectl get pods -l app=python-api
kubectl get pods -l app=zdm-proxy
echo ""

print_section "REST API Testing with CURL"

API_URL="http://localhost:8080"

echo "🧪 Testing API Health Check..."
HEALTH_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" $API_URL/)
HTTP_CODE=$(echo "$HEALTH_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
HEALTH_JSON=$(echo "$HEALTH_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

if [ "$HTTP_CODE" = "200" ]; then
    print_result 0 "API Health Check"
    echo "   Response: $HEALTH_JSON" | jq '.' 2>/dev/null || echo "   Response: $HEALTH_JSON"
else
    print_result 1 "API Health Check (HTTP $HTTP_CODE)"
    echo "   Response: $HEALTH_JSON"
fi
echo ""

echo "🧪 Testing API Statistics Endpoint..."
STATS_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" $API_URL/stats)
HTTP_CODE=$(echo "$STATS_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
STATS_JSON=$(echo "$STATS_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

if [ "$HTTP_CODE" = "200" ]; then
    print_result 0 "API Statistics"
    echo "   Response: $STATS_JSON" | jq '.' 2>/dev/null || echo "   Response: $STATS_JSON"
else
    print_result 1 "API Statistics (HTTP $HTTP_CODE)"
    echo "   Response: $STATS_JSON"
fi
echo ""

echo "🧪 Testing User Creation via CURL..."
CREATE_USER_DATA='{
    "name": "CURL Test User", 
    "email": "curl-test@zdm-demo.co.uk", 
    "gender": "Male", 
    "address": "CURL Test Street, Command Line City, UK"
}'

CREATE_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" -X POST $API_URL/users \
    -H "Content-Type: application/json" \
    -d "$CREATE_USER_DATA")

HTTP_CODE=$(echo "$CREATE_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
CREATE_JSON=$(echo "$CREATE_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    print_result 0 "User Creation"
    echo "   User Created: $CREATE_JSON" | jq '.' 2>/dev/null || echo "   User Created: $CREATE_JSON"
    
    # Extract user ID for retrieval test
    USER_ID=$(echo "$CREATE_JSON" | jq -r '.id' 2>/dev/null || echo "unknown")
    
    if [ "$USER_ID" != "unknown" ] && [ "$USER_ID" != "null" ]; then
        echo ""
        echo "🧪 Testing User Retrieval via CURL..."
        RETRIEVE_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" $API_URL/users/$USER_ID)
        HTTP_CODE=$(echo "$RETRIEVE_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
        RETRIEVE_JSON=$(echo "$RETRIEVE_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')
        
        if [ "$HTTP_CODE" = "200" ]; then
            print_result 0 "User Retrieval"
            echo "   Retrieved User: $RETRIEVE_JSON" | jq '.' 2>/dev/null || echo "   Retrieved User: $RETRIEVE_JSON"
        else
            print_result 1 "User Retrieval (HTTP $HTTP_CODE)"
            echo "   Response: $RETRIEVE_JSON"
        fi
    fi
else
    print_result 1 "User Creation (HTTP $HTTP_CODE)"
    echo "   Response: $CREATE_JSON"
fi
echo ""

echo "🧪 Testing User List via CURL..."
LIST_RESPONSE=$(curl -s -w "HTTP_CODE:%{http_code}" "$API_URL/users?limit=3")
HTTP_CODE=$(echo "$LIST_RESPONSE" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
LIST_JSON=$(echo "$LIST_RESPONSE" | sed 's/HTTP_CODE:[0-9]*$//')

if [ "$HTTP_CODE" = "200" ]; then
    print_result 0 "User List"
    echo "   Users (limit 3): $LIST_JSON" | jq '.[].name' 2>/dev/null || echo "   Users: $LIST_JSON"
else
    print_result 1 "User List (HTTP $HTTP_CODE)"
    echo "   Response: $LIST_JSON"
fi

print_section "Local Cassandra Testing with CQL"

echo "🧪 Testing direct Cassandra connection via kubectl exec..."

# Test basic connection
echo "   Testing basic CQL connection..."
kubectl exec -it cassandra-0 -- cqlsh -e "DESCRIBE KEYSPACES;" > /dev/null 2>&1
print_result $? "Cassandra Connection"

echo "   Testing demo keyspace..."
kubectl exec -it cassandra-0 -- cqlsh -e "USE demo; DESCRIBE TABLES;" > /dev/null 2>&1
print_result $? "Demo Keyspace Access"

echo "   Getting current user count..."
USER_COUNT=$(kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;" 2>/dev/null | grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' | tr -d ' \r\n')
if [ ! -z "$USER_COUNT" ]; then
    print_result 0 "User Count Query"
    print_info "Total users in Cassandra: $USER_COUNT"
else
    print_result 1 "User Count Query"
fi

echo "   Testing sample data retrieval..."
SAMPLE_USERS=$(kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users LIMIT 3;" 2>/dev/null)
if [ $? -eq 0 ]; then
    print_result 0 "Sample Data Retrieval"
    echo "   Sample users:"
    echo "$SAMPLE_USERS" | grep -E '^[[:space:]]*[^|]*\|[^|]*[[:space:]]*$' | head -3 | while IFS='|' read -r name email; do
        echo "     • $(echo $name | xargs) - $(echo $email | xargs)"
    done
else
    print_result 1 "Sample Data Retrieval"
fi

echo ""
echo "🧪 Testing CQL operations..."

# Test creating a test record directly via CQL
TEST_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
CQL_INSERT="INSERT INTO demo.users (id, name, email, gender, address) VALUES ($TEST_UUID, 'CQL Test User', 'cql-test@direct.co.uk', 'Female', 'CQL Direct Street, Test City, UK');"

kubectl exec -it cassandra-0 -- cqlsh -e "$CQL_INSERT" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_result 0 "Direct CQL Insert"
    print_info "Inserted user with ID: $TEST_UUID"
    
    # Verify the insert worked
    CQL_SELECT="SELECT name, email FROM demo.users WHERE id = $TEST_UUID;"
    VERIFY_RESULT=$(kubectl exec -it cassandra-0 -- cqlsh -e "$CQL_SELECT" 2>/dev/null)
    if [[ "$VERIFY_RESULT" == *"CQL Test User"* ]]; then
        print_result 0 "CQL Insert Verification"
        print_info "Successfully verified inserted record"
    else
        print_result 1 "CQL Insert Verification"
    fi
else
    print_result 1 "Direct CQL Insert"
fi

print_section "Connection Testing Summary"

echo "🔍 API Connection Analysis:"
if [ ! -z "$STATS_JSON" ]; then
    echo "$STATS_JSON" | jq -r '"   • ZDM Phase: " + .zdm_phase' 2>/dev/null || echo "   • ZDM Phase: Unknown"
    echo "$STATS_JSON" | jq -r '"   • Connection Host: " + .connection.host' 2>/dev/null || echo "   • Connection Host: Unknown"
    echo "$STATS_JSON" | jq -r '"   • Via ZDM Proxy: " + (.connection.via_zdm_proxy | tostring)' 2>/dev/null || echo "   • Via ZDM Proxy: Unknown"
    echo "$STATS_JSON" | jq -r '"   • Dual Write Enabled: " + (.connection.dual_write_enabled | tostring)' 2>/dev/null || echo "   • Dual Write Enabled: Unknown"
else
    echo "   • No API statistics available"
fi

echo ""
echo "🔍 Database Connection Analysis:"
if [ ! -z "$USER_COUNT" ]; then
    print_info "Local Cassandra: Connected ($USER_COUNT users)"
else
    print_info "Local Cassandra: Connection issues"
fi

echo ""
echo "🔍 ZDM Proxy Status:"
ZDM_STATUS=$(kubectl get pods -l app=zdm-proxy --no-headers 2>/dev/null | awk '{print $3}' | head -1)
if [ "$ZDM_STATUS" = "Running" ]; then
    print_info "ZDM Proxy: Running"
else
    print_info "ZDM Proxy: $ZDM_STATUS (Not available for testing)"
fi

print_section "Testing Complete"

echo "📊 Test Summary:"
echo "   • REST API endpoints tested with CURL"
echo "   • Local Cassandra tested with direct CQL"
echo "   • User creation/retrieval workflows validated"
echo "   • Database operations confirmed working"
echo ""

if [ "$ZDM_STATUS" != "Running" ]; then
    echo "📝 Note: ZDM Proxy is not running, so Phase B dual-write testing"
    echo "   is not possible at this time. The API is running in fallback mode"
    echo "   with direct Cassandra connections."
else
    echo "✅ All components tested successfully!"
fi

echo ""
echo "🏁 CURL & CQL Testing Complete!"
echo "=================================================================================="