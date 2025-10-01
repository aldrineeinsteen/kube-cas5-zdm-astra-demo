#!/usr/bin/env python3
"""
Simple Astra DB connection test with eventlet connection class
"""
import os
import json

# Configure eventlet before importing cassandra
import eventlet
eventlet.monkey_patch()

from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from cassandra.io.eventletreactor import EventletConnection

def simple_astra_test():
    """Test basic Astra DB connection"""
    
    print("🔍 Simple Astra DB connection test...")
    
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
        
        # Connect using eventlet connection class
        cluster = Cluster(
            cloud={
                'secure_connect_bundle': bundle_path
            },
            auth_provider=auth_provider,
            connection_class=EventletConnection
        )
        
        session = cluster.connect()
        print("✅ Basic connection successful!")
        
        # Test keyspace
        rows = session.execute("SELECT keyspace_name FROM system_schema.keyspaces")
        keyspaces = [row.keyspace_name for row in rows]
        print(f"📋 Available keyspaces: {keyspaces}")
        
        if 'migration_cql_demo' in keyspaces:
            print("✅ Target keyspace 'migration_cql_demo' found")
        else:
            print("⚠️  Target keyspace 'migration_cql_demo' not found")
        
        cluster.shutdown()
        return True
        
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

if __name__ == "__main__":
    success = simple_astra_test()
    exit(0 if success else 1)