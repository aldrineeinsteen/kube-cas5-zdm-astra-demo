#!/usr/bin/env python3
"""
Validate Astra DB connectivity using token-based authentication (recommended method)
"""
import os
import sys
os.environ['CASSANDRA_DRIVER_ALLOW_SYNC_IN_ASYNC'] = '1'

# Use eventlet for async support in Python 3.13
import eventlet
eventlet.monkey_patch()

from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from cassandra.policies import DCAwareRoundRobinPolicy
import json

def test_astra_token_connection():
    """Test Astra DB connection using token authentication"""
    
    print("🔍 Testing Astra DB connection with token authentication...")
    
    # Load token from JSON file
    try:
        with open("migration-cql-demo-token.json") as f:
            secrets = json.load(f)
        token = secrets["token"]
        print(f"🔐 Using token: {token[:20]}...")
    except FileNotFoundError:
        print("❌ Error: migration-cql-demo-token.json file not found")
        return False
    except KeyError:
        print("❌ Error: token field not found in JSON file")
        return False

    # Secure connect bundle
    bundle_path = "secure-connect-migration-cql-demo.zip"
    if not os.path.exists(bundle_path):
        print(f"❌ Error: Secure connect bundle not found: {bundle_path}")
        return False
    
    print(f"📦 Using bundle: {bundle_path}")

    try:
        # Use token-based authentication (recommended)
        auth_provider = PlainTextAuthProvider('token', token)
        
        cloud_config = {
            'secure_connect_bundle': bundle_path
        }
        
        cluster = Cluster(
            cloud=cloud_config, 
            auth_provider=auth_provider,
            load_balancing_policy=DCAwareRoundRobinPolicy()
        )
        
        session = cluster.connect()
        print("✅ Successfully connected to Astra DB!")
        
        # Test basic queries
        try:
            # Get version
            row = session.execute("SELECT release_version FROM system.local").one()
            if row:
                print(f"🚀 Astra DB version: {row[0]}")
            
            # Test keyspace access
            keyspaces = session.execute("SELECT keyspace_name FROM system_schema.keyspaces WHERE keyspace_name='demo'")
            demo_exists = len(list(keyspaces)) > 0
            print(f"📊 Demo keyspace exists: {demo_exists}")
            
            if demo_exists:
                # Test table access
                try:
                    count_result = session.execute("SELECT COUNT(*) FROM demo.users")
                    count = count_result.one()[0] if count_result else 0
                    print(f"👥 Users in Astra DB: {count}")
                except Exception as e:
                    print(f"⚠️  Could not query demo.users table: {e}")
            
            cluster.shutdown()
            return True
            
        except Exception as e:
            print(f"⚠️  Error during testing: {e}")
            cluster.shutdown()
            return False
            
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("🧪 ASTRA DB CONNECTION VALIDATION")
    print("=" * 60)
    
    success = test_astra_token_connection()
    
    if success:
        print("\n✅ VALIDATION PASSED - Astra DB credentials are working correctly!")
        sys.exit(0)
    else:
        print("\n❌ VALIDATION FAILED - Check your Astra DB credentials and bundle")
        sys.exit(1)