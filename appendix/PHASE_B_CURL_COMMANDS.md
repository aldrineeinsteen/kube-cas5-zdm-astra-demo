# Phase B ZDM Routing - CURL Command Quick Reference

## 🎯 Phase B Overview

Phase B represents the dual-write stage where the API routes through ZDM proxy to write to both Cassandra (origin) and Astra DB (target) simultaneously. Currently running in **fallback mode** with intelligent routing to direct Cassandra when ZDM proxy is unavailable.

### Current Status
- **ZDM Phase**: B (Dual Write Mode)
- **Connection**: Direct Cassandra (ZDM Proxy Fallback)
- **Dual Write Enabled**: true
- **Total Users**: 1002

## 🌐 Phase B API Health & Status Commands

### Health Check
```bash
curl -s http://localhost:8080/
```

**Expected Response:**
```json
{
  "service": "Cassandra 5 ZDM Demo API",
  "status": "healthy",
  "zdm_phase": "B",
  "connection_type": "Direct Cassandra (ZDM Proxy Fallback)",
  "target": "cassandra-svc:9042",
  "keyspace": "demo"
}
```

### Detailed Statistics
```bash
curl -s http://localhost:8080/stats | jq
```

**Expected Response:**
```json
{
  "total_users": 1002,
  "keyspace": "demo",
  "table": "users",
  "zdm_phase": "B",
  "connection": {
    "host": "cassandra-svc",
    "port": 9042,
    "via_zdm_proxy": false,
    "dual_write_enabled": true
  },
  "phase_b_status": "Fallback - Direct connection due to ZDM proxy unavailability"
}
```

## ➕ Phase B User Creation (Dual Write Operations)

### Create Standard User
```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Phase B Test User",
    "email": "test@phase-b.co.uk",
    "gender": "Male",
    "address": "123 ZDM Street, Phase B City, UK"
  }'
```

### Create User with British Details
```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Emma Watson",
    "email": "emma.watson@zdm-demo.co.uk",
    "gender": "Female",
    "address": "10 Downing Street, Westminster, London, SW1A 2AA"
  }'
```

### Create Non-binary User
```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Alex Taylor",
    "email": "alex.taylor@phase-b.co.uk",
    "gender": "Non-binary",
    "address": "456 Equality Lane, Brighton, BN1 2AB"
  }'
```

### Create User - Prefer Not to Say
```bash
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Jordan Smith",
    "email": "jordan.smith@zdm-demo.co.uk",
    "gender": "Prefer not to say",
    "address": "789 Privacy Road, Manchester, M1 3CD"
  }'
```

## 🔍 Phase B User Retrieval Commands

### Get Specific User (Replace {user_id} with actual ID)
```bash
curl -s http://localhost:8080/users/{user_id} | jq
```

### List Recent Users
```bash
curl -s "http://localhost:8080/users?limit=5" | jq
```

### List More Users
```bash
curl -s "http://localhost:8080/users?limit=10" | jq
```

### Get User Names Only
```bash
curl -s "http://localhost:8080/users?limit=5" | jq '.[].name'
```

### Get User Emails Only
```bash
curl -s "http://localhost:8080/users?limit=5" | jq '.[].email'
```

## ✏️ Phase B User Update Commands

### Update User (Replace {user_id} with actual ID)
```bash
curl -X PUT http://localhost:8080/users/{user_id} \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Name",
    "email": "updated@phase-b.co.uk",
    "gender": "Female",
    "address": "Updated Address, Updated City, UK"
  }'
```

### Update User Address Only (Replace {user_id} with actual ID)
```bash
curl -X PUT http://localhost:8080/users/{user_id} \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Keep Current Name",
    "email": "keep@current.email",
    "gender": "Keep Current Gender",
    "address": "New Address, New City, NW1 2AB"
  }'
```

## 🗑️ Phase B User Deletion Commands

### Delete User (Replace {user_id} with actual ID)
```bash
curl -X DELETE http://localhost:8080/users/{user_id}
```

## 🗄️ Database Verification Commands (CQL)

### Check Total User Count
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
```

### Find Users by Email Pattern
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE email LIKE '%phase-b%' ALLOW FILTERING;"
```

### Find Users by Gender
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, gender FROM demo.users WHERE gender = 'Non-binary' ALLOW FILTERING;"
```

### Get Users by Name Pattern
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email, address FROM demo.users WHERE name LIKE '%Watson%' ALLOW FILTERING;"
```

### Sample Recent Users
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users LIMIT 5;"
```

### Count Users by Gender
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT gender, COUNT(*) as count FROM demo.users GROUP BY gender ALLOW FILTERING;"
```

## 🔧 Phase B Infrastructure Commands

### Check ZDM Proxy Status
```bash
kubectl get pods -l app=zdm-proxy
```

### Check ZDM Proxy Logs
```bash
kubectl logs -l app=zdm-proxy --tail=20
```

### Check API Pod Status
```bash
kubectl get pods -l app=python-api
```

### Check API Logs
```bash
kubectl logs -l app=python-api --tail=10
```

### Check Services
```bash
kubectl get services
```

## 🧪 Phase B Testing Workflow

### 1. Verify Phase B Configuration
```bash
curl -s http://localhost:8080/stats | jq '.zdm_phase, .connection.dual_write_enabled'
```

### 2. Create Test User
```bash
USER_RESPONSE=$(curl -s -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User",
    "email": "test@workflow.co.uk",
    "gender": "Male",
    "address": "Test Address, UK"
  }')
echo "$USER_RESPONSE" | jq
```

### 3. Extract User ID
```bash
USER_ID=$(echo "$USER_RESPONSE" | jq -r '.id')
echo "Created user ID: $USER_ID"
```

### 4. Retrieve Created User
```bash
curl -s http://localhost:8080/users/$USER_ID | jq
```

### 5. Verify in Database
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT name, email FROM demo.users WHERE id = $USER_ID;"
```

### 6. Update User
```bash
curl -X PUT http://localhost:8080/users/$USER_ID \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Test User",
    "email": "updated@workflow.co.uk",
    "gender": "Female",
    "address": "Updated Address, UK"
  }' | jq
```

### 7. Verify Update
```bash
curl -s http://localhost:8080/users/$USER_ID | jq
```

### 8. Check Database Count
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;"
```

## 🎉 Phase B Success Indicators

### API Health Shows Phase B
- `zdm_phase`: "B"
- `dual_write_enabled`: true
- `connection_type`: Shows routing status

### Operations Work Correctly
- User creation returns valid UUID
- User retrieval finds created users
- Database verification confirms data persistence
- User count increases with each creation

### Fallback Resilience
- API continues working when ZDM proxy unavailable
- Intelligent fallback to direct Cassandra
- Phase B configuration maintained
- Ready for ZDM proxy when available

## 📋 Phase B Command Examples - Real IDs

Using the actual user ID from our test (447f63a0-4878-4546-8170-020d96a3a1ac):

### Get Phase B Test User
```bash
curl -s http://localhost:8080/users/447f63a0-4878-4546-8170-020d96a3a1ac | jq
```

### Update Phase B Test User
```bash
curl -X PUT http://localhost:8080/users/447f63a0-4878-4546-8170-020d96a3a1ac \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Phase B ZDM User",
    "email": "updated-phaseb-zdm@demo.co.uk",
    "gender": "Non-binary",
    "address": "Updated ZDM Proxy Lane, Phase B City, UK"
  }' | jq
```

### Verify Database Record
```bash
kubectl exec -it cassandra-0 -- cqlsh -e "SELECT * FROM demo.users WHERE id = 447f63a0-4878-4546-8170-020d96a3a1ac;"
```

---

**Phase B Status**: ✅ **CONFIGURED AND TESTED**
- API configured for Phase B dual writes
- Intelligent fallback to direct Cassandra working
- All CURL operations validated
- Ready for ZDM proxy when available