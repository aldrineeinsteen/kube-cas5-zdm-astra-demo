#!/bin/bash
# Phase A Testing Script - Direct Cassandra Connection (No ZDM)
# Tests API functionality and validates Phase A configuration

echo "🚀 Starting Phase A API Testing (Direct Cassandra)"
echo "============================================================"

# Test 1: API Health Check
echo ""
echo "📋 Test 1: API Health Check"
echo "----------------------------"
HEALTH_RESPONSE=$(curl -s http://localhost:8080/)
echo "Response: $HEALTH_RESPONSE"

# Extract phase information
CURRENT_PHASE=$(echo $HEALTH_RESPONSE | jq -r '.zdm_phase // "unknown"')
CONNECTION_TYPE=$(echo $HEALTH_RESPONSE | jq -r '.connection_type // "unknown"')
TARGET=$(echo $HEALTH_RESPONSE | jq -r '.target // "unknown"')

echo "Current Phase: $CURRENT_PHASE"
echo "Connection Type: $CONNECTION_TYPE"
echo "Target: $TARGET"

# Test 2: Database Statistics
echo ""
echo "📊 Test 2: Database Statistics"
echo "------------------------------"
STATS_RESPONSE=$(curl -s http://localhost:8080/stats)
echo "Stats Response: $STATS_RESPONSE"

TOTAL_USERS=$(echo $STATS_RESPONSE | jq -r '.total_users // 0')
KEYSPACE=$(echo $STATS_RESPONSE | jq -r '.keyspace // "unknown"')
CASSANDRA_HOST=$(echo $STATS_RESPONSE | jq -r '.connection.host // "unknown"')

echo "Total Users: $TOTAL_USERS"
echo "Keyspace: $KEYSPACE"
echo "Cassandra Host: $CASSANDRA_HOST"

# Test 3: Create New User
echo ""
echo "👤 Test 3: Create New User"
echo "--------------------------"
CREATE_RESPONSE=$(curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase Test User",
    "email": "phase-test@zdm-demo.co.uk",
    "gender": "Female",
    "address": "123 Test Street, London, SW1A 1AA"
  }')

echo "Create Response: $CREATE_RESPONSE"
USER_ID=$(echo $CREATE_RESPONSE | jq -r '.id // "none"')
echo "Created User ID: $USER_ID"

# Test 4: Retrieve Created User
if [ "$USER_ID" != "none" ] && [ "$USER_ID" != "null" ]; then
    echo ""
    echo "🔍 Test 4: Retrieve Created User"
    echo "--------------------------------"
    GET_RESPONSE=$(curl -s http://localhost:8080/users/$USER_ID)
    echo "Get Response: $GET_RESPONSE"
    
    USER_NAME=$(echo $GET_RESPONSE | jq -r '.name // "unknown"')
    echo "Retrieved User Name: $USER_NAME"
else
    echo ""
    echo "⚠️  Test 4: Skipped (User creation failed)"
fi

# Test 5: List Recent Users
echo ""
echo "📝 Test 5: List Recent Users (Limit 5)"
echo "--------------------------------------"
LIST_RESPONSE=$(curl -s "http://localhost:8080/users?limit=5")
echo "List Response: $LIST_RESPONSE"

USER_COUNT=$(echo $LIST_RESPONSE | jq '. | length')
echo "Users Retrieved: $USER_COUNT"

# Test 6: Updated Statistics
echo ""
echo "📈 Test 6: Updated Statistics"
echo "-----------------------------"
FINAL_STATS=$(curl -s http://localhost:8080/stats)
FINAL_COUNT=$(echo $FINAL_STATS | jq -r '.total_users // 0')
echo "Final User Count: $FINAL_COUNT"
echo "Users Added: $((FINAL_COUNT - TOTAL_USERS))"

# Test 7: Direct Cassandra Verification
echo ""
echo "🗃️  Test 7: Direct Cassandra Verification"
echo "----------------------------------------"
echo "Verifying data exists in Cassandra..."
if kubectl get pods cassandra-0 > /dev/null 2>&1; then
    CASSANDRA_COUNT=$(kubectl exec cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;" 2>/dev/null | grep -E '^[[:space:]]*[0-9]+' | tr -d ' ')
    echo "Cassandra User Count: $CASSANDRA_COUNT"
    
    if [ "$USER_ID" != "none" ] && [ "$USER_ID" != "null" ]; then
        echo "Checking for created user in Cassandra..."
        kubectl exec cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE name = 'Phase Test User' ALLOW FILTERING;" 2>/dev/null || echo "User query failed"
    fi
else
    echo "❌ Cassandra pod not accessible"
fi

# Summary
echo ""
echo "📋 PHASE A TEST SUMMARY"
echo "======================="
echo "Phase: $CURRENT_PHASE"
echo "Connection: $CONNECTION_TYPE"
echo "Target: $TARGET"
echo "Initial Users: $TOTAL_USERS"
echo "Final Users: $FINAL_COUNT"
echo "Test User Created: $([ "$USER_ID" != "none" ] && [ "$USER_ID" != "null" ] && echo "✅ Yes" || echo "❌ No")"
echo "API Responsive: $([ ! -z "$HEALTH_RESPONSE" ] && echo "✅ Yes" || echo "❌ No")"

if [ "$CURRENT_PHASE" = "A" ] && [ "$CONNECTION_TYPE" = "Direct Cassandra" ]; then
    echo "✅ PHASE A TESTING SUCCESSFUL - Direct Cassandra connection confirmed"
else
    echo "⚠️  Phase configuration may not be as expected"
fi

echo ""
echo "🎯 Use this script to validate Phase A before transitioning to Phase B"