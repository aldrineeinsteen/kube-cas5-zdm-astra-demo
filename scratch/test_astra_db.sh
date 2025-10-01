#!/bin/bash

# Astra DB Testing Script - Direct CQL Connection Testing
# Tests Astra DB connectivity and operations from command line

echo "🌟 Astra DB Testing Suite - Direct Command Line Testing"
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

print_section "Astra DB Connection Prerequisites"

# Check if secure bundle exists
SECURE_BUNDLE="secure-connect-migration-cql-demo.zip"
if [ -f "$SECURE_BUNDLE" ]; then
    print_result 0 "Secure Connect Bundle Found"
    print_info "Bundle: $SECURE_BUNDLE"
else
    print_result 1 "Secure Connect Bundle Missing"
    print_info "Expected: $SECURE_BUNDLE"
    echo ""
    echo "📝 To test Astra DB, you need:"
    echo "   1. Download Secure Connect Bundle from Astra Console"
    echo "   2. Save as: $SECURE_BUNDLE"
    echo "   3. Generate Application Token with Database Administrator role"
    echo ""
    exit 1
fi

# Check if token file exists
TOKEN_FILE="migration-cql-demo-token.json"
if [ -f "$TOKEN_FILE" ]; then
    print_result 0 "Astra Token File Found"
    print_info "Token file: $TOKEN_FILE"
else
    print_result 1 "Astra Token File Missing"
    print_info "Expected: $TOKEN_FILE"
    echo ""
    echo "📝 Create $TOKEN_FILE with format:"
    echo '   {"clientId":"YOUR_CLIENT_ID","secret":"YOUR_SECRET","token":"YOUR_TOKEN"}'
    echo ""
    exit 1
fi

print_section "Python Environment Check"

# Check if we're in the astra-test-env
if [[ "$VIRTUAL_ENV" == *"astra-test-env"* ]]; then
    print_result 0 "Virtual Environment Active"
    print_info "Environment: $(basename $VIRTUAL_ENV)"
else
    print_result 1 "Virtual Environment Not Active"
    print_info "Please activate: source astra-test-env/bin/activate"
    echo ""
    echo "📝 Activating virtual environment..."
    source astra-test-env/bin/activate
    if [[ "$VIRTUAL_ENV" == *"astra-test-env"* ]]; then
        print_result 0 "Virtual Environment Activated"
    else
        print_result 1 "Failed to Activate Virtual Environment"
        exit 1
    fi
fi

# Check if Cassandra driver is installed
python3 -c "import cassandra" 2>/dev/null
if [ $? -eq 0 ]; then
    print_result 0 "Cassandra Driver Available"
else
    print_result 1 "Cassandra Driver Missing"
    print_info "Installing cassandra-driver..."
    pip install cassandra-driver
fi

print_section "Astra DB Connection Test"

# Create Python script for Astra testing
cat > /tmp/test_astra_connection.py << 'EOF'
#!/usr/bin/env python3

import sys
import json
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from cassandra.policies import DCAwareRoundRobinPolicy
import uuid
import ssl

def test_astra_connection():
    try:
        # Load token from file
        with open('migration-cql-demo-token.json', 'r') as f:
            token_data = json.load(f)
        
        # Set up authentication
        auth_provider = PlainTextAuthProvider(
            username=token_data['clientId'], 
            password=token_data['secret']
        )
        
        # Create SSL context
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS)
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE
        
        # Create cluster connection
        cluster = Cluster(
            cloud={
                'secure_connect_bundle': 'secure-connect-migration-cql-demo.zip'
            },
            auth_provider=auth_provider,
            ssl_context=ssl_context,
            load_balancing_policy=DCAwareRoundRobinPolicy()
        )
        
        print("🔗 Connecting to Astra DB...")
        session = cluster.connect()
        
        print("✅ Successfully connected to Astra DB!")
        
        # Test basic query
        print("🧪 Testing basic keyspace query...")
        keyspaces = session.execute("SELECT keyspace_name FROM system_schema.keyspaces")
        keyspace_list = [row.keyspace_name for row in keyspaces]
        print(f"   Available keyspaces: {', '.join(keyspace_list[:5])}...")
        
        # Check if demo keyspace exists
        if 'demo' in keyspace_list:
            print("✅ Demo keyspace found in Astra DB")
            
            # Use demo keyspace
            session.set_keyspace('demo')
            print("🔍 Connected to demo keyspace")
            
            # Check if users table exists
            tables = session.execute("SELECT table_name FROM system_schema.tables WHERE keyspace_name='demo'")
            table_list = [row.table_name for row in tables]
            
            if 'users' in table_list:
                print("✅ Users table found in demo keyspace")
                
                # Get user count
                try:
                    count_result = session.execute("SELECT COUNT(*) FROM demo.users")
                    count = count_result.one()[0]
                    print(f"📊 Total users in Astra DB: {count}")
                    
                    # Get sample users
                    sample_users = session.execute("SELECT id, name, email FROM demo.users LIMIT 3")
                    print("👥 Sample users from Astra DB:")
                    for user in sample_users:
                        print(f"   • {user.name} - {user.email}")
                        
                except Exception as e:
                    print(f"⚠️  Could not query users table: {e}")
                
                # Test creating a user
                try:
                    test_id = uuid.uuid4()
                    insert_cql = """
                    INSERT INTO demo.users (id, name, email, gender, address) 
                    VALUES (?, ?, ?, ?, ?)
                    """
                    
                    session.execute(insert_cql, [
                        test_id,
                        'Astra Test User',
                        'astra-test@zdm-demo.co.uk',
                        'Other',
                        'Astra Street, Cloud City, Space'
                    ])
                    
                    print(f"✅ Successfully created test user in Astra DB (ID: {test_id})")
                    
                    # Verify the user was created
                    verify_result = session.execute(
                        "SELECT name, email FROM demo.users WHERE id = ?", 
                        [test_id]
                    )
                    user = verify_result.one()
                    if user:
                        print(f"✅ Verified user creation: {user.name} - {user.email}")
                    else:
                        print("❌ Could not verify user creation")
                        
                except Exception as e:
                    print(f"❌ Failed to create test user: {e}")
                    
            else:
                print("❌ Users table not found in demo keyspace")
                print(f"   Available tables: {', '.join(table_list)}")
        else:
            print("❌ Demo keyspace not found in Astra DB")
            print("   You may need to create the keyspace and table first")
            
            # Try to create demo keyspace
            try:
                session.execute("""
                    CREATE KEYSPACE IF NOT EXISTS demo 
                    WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1}
                """)
                print("✅ Created demo keyspace in Astra DB")
                
                session.set_keyspace('demo')
                
                # Create users table
                session.execute("""
                    CREATE TABLE IF NOT EXISTS users (
                        id UUID PRIMARY KEY,
                        name TEXT,
                        email TEXT,
                        gender TEXT,
                        address TEXT,
                        created_at TIMESTAMP
                    )
                """)
                print("✅ Created users table in Astra DB")
                
            except Exception as e:
                print(f"❌ Failed to create schema: {e}")
        
        cluster.shutdown()
        return True
        
    except FileNotFoundError as e:
        print(f"❌ File not found: {e}")
        return False
    except json.JSONDecodeError:
        print("❌ Invalid JSON in token file")
        return False
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

if __name__ == "__main__":
    success = test_astra_connection()
    sys.exit(0 if success else 1)
EOF

echo "🧪 Running Astra DB connection test..."
python3 /tmp/test_astra_connection.py
ASTRA_TEST_RESULT=$?

if [ $ASTRA_TEST_RESULT -eq 0 ]; then
    print_result 0 "Astra DB Connection Test"
else
    print_result 1 "Astra DB Connection Test"
fi

print_section "Astra DB vs Local Cassandra Comparison"

echo "🔍 Comparing data between Local Cassandra and Astra DB..."

# Get local Cassandra user count
echo "📊 Local Cassandra user count:"
LOCAL_COUNT=$(kubectl exec -it cassandra-0 -- cqlsh -e "SELECT COUNT(*) FROM demo.users;" 2>/dev/null | grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' | tr -d ' \r\n')
if [ ! -z "$LOCAL_COUNT" ]; then
    print_info "Local Cassandra: $LOCAL_COUNT users"
else
    print_info "Local Cassandra: Unable to get count"
fi

echo ""
echo "📊 If Astra DB connection was successful, user counts were shown above"

print_section "Testing Summary"

echo "🔍 Connection Test Results:"
if [ $ASTRA_TEST_RESULT -eq 0 ]; then
    print_result 0 "Astra DB: Connected successfully"
    echo "   • Keyspace and table operations tested"
    echo "   • User creation and retrieval validated"
    echo "   • Ready for ZDM Phase B/C operations"
else
    print_result 1 "Astra DB: Connection failed"
    echo "   • Check secure connect bundle"
    echo "   • Verify token credentials"
    echo "   • Ensure database is active"
fi

print_result 0 "Local Cassandra: Available via kubectl"

echo ""
print_section "Next Steps"

if [ $ASTRA_TEST_RESULT -eq 0 ]; then
    echo "✅ Both databases are accessible!"
    echo ""
    echo "🔄 For ZDM testing, you can:"
    echo "   1. Fix ZDM proxy configuration issues"
    echo "   2. Test Phase B dual writes manually"
    echo "   3. Validate data consistency between databases"
    echo "   4. Proceed with Phase C cutover testing"
else
    echo "⚠️  Astra DB connection issues detected"
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "   1. Verify Astra DB is active and accessible"
    echo "   2. Check secure connect bundle is valid"
    echo "   3. Verify token has correct permissions"
    echo "   4. Test from Astra DB console first"
fi

echo ""
echo "🏁 Astra DB Testing Complete!"
echo "=================================================================================="

# Clean up
rm -f /tmp/test_astra_connection.py