#!/usr/bin/env python3
"""
Create the migration_cql_demo keyspace and users table in Astra DB
"""
import json
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

def setup_astra_schema():
    """Create keyspace and table in Astra DB"""
    
    print("🏗️  Setting up Astra DB schema...")
    
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
    
    # Create keyspace
    print("📋 Creating keyspace 'migration_cql_demo'...")
    session.execute("""
        CREATE KEYSPACE IF NOT EXISTS migration_cql_demo
        WITH replication = {'class': 'NetworkTopologyStrategy', 'us-east1': 3}
    """)
    
    # Use the keyspace
    session.set_keyspace('migration_cql_demo')
    
    # Create users table
    print("👥 Creating users table...")
    session.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY,
            name TEXT,
            email TEXT,
            gender TEXT,
            address TEXT
        )
    """)
    
    # Verify schema
    print("✅ Schema created successfully!")
    
    # Check if table is accessible
    try:
        result = session.execute("SELECT COUNT(*) FROM users")
        count = result.one()[0]
        print(f"📊 Users table ready, current count: {count}")
    except Exception as e:
        print(f"⚠️  Table verification warning: {e}")
    
    cluster.shutdown()
    print("🎉 Astra DB schema setup complete!")

if __name__ == "__main__":
    setup_astra_schema()