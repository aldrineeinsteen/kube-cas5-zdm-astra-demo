#!/usr/bin/env python3
"""
Test Astra DB permissions and create table in available keyspace
"""
import json
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

def setup_astra_table():
    """Create table in available Astra DB keyspace"""
    
    print("🏗️  Setting up Astra DB table...")
    
    # Load token
    with open("migration-cql-demo-token.json") as f:
        token = json.load(f)["token"]
    
    # Connect to Astra
    auth_provider = PlainTextAuthProvider('token', token)
    cluster = Cluster(
        cloud={'secure_connect_bundle': 'secure-connect-migration-cql-demo.zip'},
        auth_provider=auth_provider
    )
    session = cluster.connect()
    
    # Check available keyspaces
    rows = session.execute("SELECT keyspace_name FROM system_schema.keyspaces")
    keyspaces = [row.keyspace_name for row in rows if not row.keyspace_name.startswith('system')]
    print(f"📋 Available non-system keyspaces: {keyspaces}")
    
    # Try to use the 'demo' keyspace
    if 'demo' in keyspaces:
        print("🎯 Using 'demo' keyspace...")
        session.set_keyspace('demo')
        
        # Create users table
        print("👥 Creating users table in demo keyspace...")
        try:
            session.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id UUID PRIMARY KEY,
                    name TEXT,
                    email TEXT,
                    gender TEXT,
                    address TEXT
                )
            """)
            print("✅ Users table created successfully!")
            
            # Test access
            result = session.execute("SELECT COUNT(*) FROM users")
            count = result.one()[0]
            print(f"📊 Users table accessible, count: {count}")
            
        except Exception as e:
            print(f"❌ Table creation failed: {e}")
            
    else:
        print("❌ No suitable keyspace found for table creation")
    
    cluster.shutdown()
    print("🎉 Astra DB table setup complete!")

if __name__ == "__main__":
    setup_astra_table()