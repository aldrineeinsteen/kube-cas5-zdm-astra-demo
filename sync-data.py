#!/usr/bin/env python3
"""
Data synchronization script for migrating existing data from Cassandra to Astra DB.
This implements DataStax Phase 2: Migrate Existing Data

Usage:
    python sync-data.py [--dry-run] [--batch-size=1000]
"""

import os
import sys
import json
import argparse
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from cassandra.policies import DCAwareRoundRobinPolicy
import uuid
from typing import List, Dict, Any
import time

def load_astra_config():
    """Load Astra DB configuration from secure connect bundle and token"""
    
    # Load secure connect bundle path
    bundle_path = os.getenv('ASTRA_SECURE_BUNDLE_PATH', './secure-connect-migration-cql-demo.zip')
    if not os.path.exists(bundle_path):
        raise FileNotFoundError(f"Astra secure connect bundle not found: {bundle_path}")
    
    # Load Astra token from JSON file
    token_file = os.getenv('ASTRA_TOKEN_FILE_PATH', './migration-cql-demo-token.json')
    if not os.path.exists(token_file):
        raise FileNotFoundError(f"Astra token file not found: {token_file}")
    
    with open(token_file, 'r') as f:
        token_data = json.load(f)
    
    return {
        'secure_connect_bundle': bundle_path,
        'username': 'token',
        'password': token_data['token']
    }

def connect_to_cassandra():
    """Connect to local Cassandra cluster"""
    print("Connecting to Cassandra...")
    
    cluster = Cluster(
        contact_points=['127.0.0.1'],
        port=30041,  # NodePort for Cassandra
        auth_provider=PlainTextAuthProvider(username='cassandra', password='cassandra')
    )
    
    session = cluster.connect()
    session.set_keyspace('demo')
    print("✅ Connected to Cassandra")
    return cluster, session

def connect_to_astra():
    """Connect to Astra DB"""
    print("Connecting to Astra DB...")
    
    config = load_astra_config()
    
    cluster = Cluster(
        cloud={
            'secure_connect_bundle': config['secure_connect_bundle']
        },
        auth_provider=PlainTextAuthProvider(
            username=config['username'],
            password=config['password']
        )
    )
    
    session = cluster.connect()
    session.set_keyspace('demo')
    print("✅ Connected to Astra DB")
    return cluster, session

def get_cassandra_data(cassandra_session, batch_size: int = 1000) -> List[Dict[str, Any]]:
    """Fetch all data from Cassandra"""
    print(f"Fetching data from Cassandra (batch size: {batch_size})...")
    
    query = "SELECT id, name, email, gender, address FROM demo.users"
    result = cassandra_session.execute(query)
    
    rows = []
    for row in result:
        rows.append({
            'id': row.id,
            'name': row.name,
            'email': row.email,
            'gender': row.gender,
            'address': row.address
        })
    
    print(f"✅ Fetched {len(rows)} records from Cassandra")
    return rows

def get_astra_existing_ids(astra_session) -> set:
    """Get existing IDs in Astra DB to avoid duplicates"""
    print("Checking existing records in Astra DB...")
    
    query = "SELECT id FROM demo.users"
    result = astra_session.execute(query)
    
    existing_ids = {row.id for row in result}
    print(f"✅ Found {len(existing_ids)} existing records in Astra DB")
    return existing_ids

def sync_data_to_astra(astra_session, rows: List[Dict[str, Any]], existing_ids: set, dry_run: bool = False):
    """Sync data to Astra DB, skipping existing records"""
    
    # Filter out existing records
    new_rows = [row for row in rows if row['id'] not in existing_ids]
    
    if not new_rows:
        print("✅ No new records to sync - all data already exists in Astra DB")
        return 0
    
    print(f"Syncing {len(new_rows)} new records to Astra DB...")
    
    if dry_run:
        print("🔍 DRY RUN - Would sync the following records:")
        for i, row in enumerate(new_rows[:5]):  # Show first 5
            print(f"  {i+1}. {row['name']} ({row['email']})")
        if len(new_rows) > 5:
            print(f"  ... and {len(new_rows) - 5} more records")
        return len(new_rows)
    
    # Prepare insert statement
    insert_stmt = astra_session.prepare("""
        INSERT INTO demo.users (id, name, email, gender, address)
        VALUES (?, ?, ?, ?, ?)
    """)
    
    # Batch insert
    batch_size = 100
    synced_count = 0
    
    for i in range(0, len(new_rows), batch_size):
        batch = new_rows[i:i + batch_size]
        
        for row in batch:
            astra_session.execute(insert_stmt, [
                row['id'],
                row['name'],
                row['email'],
                row['gender'],
                row['address']
            ])
            synced_count += 1
        
        print(f"Progress: {synced_count}/{len(new_rows)} records synced")
        time.sleep(0.1)  # Small delay to avoid overwhelming Astra DB
    
    print(f"✅ Successfully synced {synced_count} records to Astra DB")
    return synced_count

def validate_sync(cassandra_session, astra_session):
    """Validate that data counts match"""
    print("\nValidating synchronization...")
    
    # Count records in both clusters
    cassandra_count = cassandra_session.execute("SELECT COUNT(*) FROM demo.users").one().count
    astra_count = astra_session.execute("SELECT COUNT(*) FROM demo.users").one().count
    
    print(f"Cassandra records: {cassandra_count}")
    print(f"Astra DB records: {astra_count}")
    
    if cassandra_count == astra_count:
        print("✅ Data sync validation PASSED - record counts match")
        return True
    else:
        print(f"❌ Data sync validation FAILED - mismatch: {cassandra_count} vs {astra_count}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Sync data from Cassandra to Astra DB')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be synced without making changes')
    parser.add_argument('--batch-size', type=int, default=1000, help='Batch size for fetching data')
    
    args = parser.parse_args()
    
    print("🚀 Starting DataStax Phase 2: Data Migration")
    print("=" * 50)
    
    try:
        # Connect to both clusters
        cassandra_cluster, cassandra_session = connect_to_cassandra()
        astra_cluster, astra_session = connect_to_astra()
        
        # Fetch data from Cassandra
        cassandra_data = get_cassandra_data(cassandra_session, args.batch_size)
        
        # Get existing IDs in Astra
        existing_ids = get_astra_existing_ids(astra_session)
        
        # Sync data
        synced_count = sync_data_to_astra(
            astra_session, 
            cassandra_data, 
            existing_ids, 
            dry_run=args.dry_run
        )
        
        if not args.dry_run and synced_count > 0:
            # Validate sync
            validation_passed = validate_sync(cassandra_session, astra_session)
            
            if validation_passed:
                print("\n🎉 Data migration completed successfully!")
                print("Next step: Proceed to ZDM Phase 3 (async dual reads) or Phase 4 (route reads to target)")
            else:
                print("\n⚠️  Data migration completed but validation failed")
                print("Please check the data manually and reconcile any differences")
        
        # Close connections
        cassandra_cluster.shutdown()
        astra_cluster.shutdown()
        
    except Exception as e:
        print(f"❌ Error during data migration: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
