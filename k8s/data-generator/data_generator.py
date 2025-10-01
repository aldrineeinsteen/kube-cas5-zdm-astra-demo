#!/usr/bin/env python3
"""
Data Generator for Cassandra 5 ZDM Demo
Generates demo data with UUID, name, email, gender, address fields
"""

import os
import sys
import uuid
import random
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from faker import Faker

# Configuration from environment variables
CASSANDRA_HOST = os.getenv('CASSANDRA_HOST', 'cassandra-svc')
CASSANDRA_PORT = int(os.getenv('CASSANDRA_PORT', '9042'))
CASSANDRA_USERNAME = os.getenv('CASSANDRA_USERNAME', 'cassandra')
CASSANDRA_PASSWORD = os.getenv('CASSANDRA_PASSWORD', 'cassandra')
KEYSPACE = os.getenv('KEYSPACE', 'demo')
TABLE = os.getenv('TABLE', 'users')
ROW_COUNT = int(os.getenv('ROW_COUNT', '1000'))

fake = Faker(['en_GB'])  # British English as specified

def connect_to_cassandra():
    """Connect to Cassandra cluster with retries"""
    auth_provider = PlainTextAuthProvider(
        username=CASSANDRA_USERNAME,
        password=CASSANDRA_PASSWORD
    )
    
    cluster = Cluster(
        [CASSANDRA_HOST],
        port=CASSANDRA_PORT,
        auth_provider=auth_provider,
        connect_timeout=30,
        control_connection_timeout=30
    )
    
    max_retries = 10
    for attempt in range(max_retries):
        try:
            session = cluster.connect()
            print(f"Connected to Cassandra at {CASSANDRA_HOST}:{CASSANDRA_PORT}")
            return cluster, session
        except Exception as e:
            print(f"Connection attempt {attempt + 1}/{max_retries} failed: {e}")
            if attempt < max_retries - 1:
                import time
                time.sleep(10)
            else:
                print("Failed to connect to Cassandra after all retries")
                raise

def create_keyspace_and_table(session):
    """Create keyspace and table if they don't exist"""
    
    # Create keyspace
    keyspace_cql = f"""
    CREATE KEYSPACE IF NOT EXISTS {KEYSPACE}
    WITH REPLICATION = {{
        'class': 'SimpleStrategy',
        'replication_factor': 1
    }}
    """
    session.execute(keyspace_cql)
    print(f"Keyspace '{KEYSPACE}' created/verified")
    
    # Use keyspace
    session.set_keyspace(KEYSPACE)
    
    # Create table
    table_cql = f"""
    CREATE TABLE IF NOT EXISTS {TABLE} (
        id UUID PRIMARY KEY,
        name TEXT,
        email TEXT,
        gender TEXT,
        address TEXT
    )
    """
    session.execute(table_cql)
    print(f"Table '{KEYSPACE}.{TABLE}' created/verified")

def generate_demo_data(session):
    """Generate and insert demo data"""
    print(f"Generating {ROW_COUNT} rows of demo data...")
    
    insert_cql = f"""
    INSERT INTO {TABLE} (id, name, email, gender, address)
    VALUES (?, ?, ?, ?, ?)
    """
    prepared = session.prepare(insert_cql)
    
    batch_size = 100
    inserted = 0
    
    for i in range(ROW_COUNT):
        user_id = uuid.uuid4()
        name = fake.name()
        email = fake.email()
        gender = random.choice(['Male', 'Female', 'Non-binary', 'Prefer not to say'])
        address = fake.address().replace('\n', ', ')
        
        try:
            session.execute(prepared, (user_id, name, email, gender, address))
            inserted += 1
            
            if (i + 1) % batch_size == 0:
                print(f"Inserted {i + 1}/{ROW_COUNT} rows...")
                
        except Exception as e:
            print(f"Error inserting row {i + 1}: {e}")
    
    print(f"Successfully inserted {inserted} rows into {KEYSPACE}.{TABLE}")
    return inserted

def verify_data(session):
    """Verify data was inserted correctly"""
    count_cql = f"SELECT COUNT(*) FROM {TABLE}"
    result = session.execute(count_cql)
    count = result.one()[0]
    print(f"Verification: {count} total rows in {KEYSPACE}.{TABLE}")
    
    # Show a few sample records
    sample_cql = f"SELECT id, name, email, gender FROM {TABLE} LIMIT 5"
    results = session.execute(sample_cql)
    
    print("Sample records:")
    for row in results:
        print(f"  {row.id} | {row.name} | {row.email} | {row.gender}")

def main():
    """Main execution function"""
    print("=== Cassandra 5 ZDM Demo Data Generator ===")
    print(f"Target: {CASSANDRA_HOST}:{CASSANDRA_PORT}")
    print(f"Keyspace: {KEYSPACE}")
    print(f"Table: {TABLE}")
    print(f"Rows to generate: {ROW_COUNT}")
    print()
    
    try:
        # Connect to Cassandra
        cluster, session = connect_to_cassandra()
        
        # Create keyspace and table
        create_keyspace_and_table(session)
        
        # Generate demo data
        inserted_count = generate_demo_data(session)
        
        # Verify data
        verify_data(session)
        
        print(f"\n✅ Data generation completed successfully!")
        print(f"   Generated {inserted_count} records in {KEYSPACE}.{TABLE}")
        
    except Exception as e:
        print(f"\n❌ Data generation failed: {e}")
        sys.exit(1)
    
    finally:
        if 'cluster' in locals():
            cluster.shutdown()

if __name__ == "__main__":
    main()