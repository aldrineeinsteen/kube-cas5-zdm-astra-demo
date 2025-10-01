#!/usr/bin/env python3
"""
Minimal Astra DB connection test for Python 3.9
"""
import os
import json
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

def test_astra_python39():
    """Test Astra DB connection with Python 3.9"""
    
    print("🔍 Testing Astra DB with Python 3.9...")
    
    # Load token
    try:
        with open("migration-cql-demo-token.json") as f:
            secrets = json.load(f)
        token = secrets["token"]
        print(f"🔐 Token loaded: {token[:20]}...")
    except Exception as e:
        print(f"❌ Token loading failed: {e}")
        return False
    
    # Check bundle file
    bundle_path = "secure-connect-migration-cql-demo.zip"
    if not os.path.exists(bundle_path):
        print(f"❌ Bundle file not found: {bundle_path}")
        return False
    
    print(f"📦 Bundle found: {bundle_path}")
    
    try:
        # Create auth provider
        auth_provider = PlainTextAuthProvider('token', token)
        
        # Connect to Astra DB
        cluster = Cluster(
            cloud={
                'secure_connect_bundle': bundle_path
            },
            auth_provider=auth_provider
        )
        
        print("🔌 Attempting connection...")
        session = cluster.connect()
        print("✅ Connection successful!")
        
        # Test basic query
        rows = session.execute("SELECT keyspace_name FROM system_schema.keyspaces")
        keyspaces = [row.keyspace_name for row in rows]
        print(f"📋 Available keyspaces: {keyspaces}")
        
        if 'migration_cql_demo' in keyspaces:
            print("✅ Target keyspace 'migration_cql_demo' found")
            
            # Test table access
            try:
                session.set_keyspace('migration_cql_demo')
                result = session.execute("SELECT COUNT(*) FROM users LIMIT 1")
                count = result.one()[0]
                print(f"📊 Users table accessible, count: {count}")
            except Exception as e:
                print(f"⚠️  Cannot access users table: {e}")
        else:
            print("⚠️  Target keyspace 'migration_cql_demo' not found")
            print("📝 Available keyspaces for reference:")
            for ks in keyspaces:
                print(f"   - {ks}")
        
        cluster.shutdown()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

if __name__ == "__main__":
    success = test_astra_python39()
    print("\n" + "="*50)
    if success:
        print("🎉 ASTRA DB CONNECTION VALIDATION SUCCESSFUL!")
        print("✅ Credentials are working correctly")
    else:
        print("❌ ASTRA DB CONNECTION VALIDATION FAILED")
        print("🔧 Check your credentials and bundle file")
    print("="*50)
    
    exit(0 if success else 1)