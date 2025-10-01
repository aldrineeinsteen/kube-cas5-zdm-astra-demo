#!/usr/bin/env python3
"""
Phase B Dual Write Test - Demonstrate writing to both Cassandra and Astra DB
This simulates what the ZDM proxy would do in Phase B mode.
"""
import sys
import os
import json
import uuid
from datetime import datetime

# Add current directory to path for imports
sys.path.append('.')

try:
    from cassandra.cluster import Cluster
    from cassandra.auth import PlainTextAuthProvider
    from cassandra.policies import DCAwareRoundRobinPolicy
except ImportError:
    print("❌ Error: cassandra-driver not installed")
    print("Please run: pip install cassandra-driver")
    sys.exit(1)

class DualWriteTest:
    def __init__(self):
        self.cassandra_session = None
        self.astra_session = None
        self.test_results = {
            'cassandra_connection': False,
            'astra_connection': False,
            'dual_write_success': False,
            'data_consistency': False
        }

    def connect_to_cassandra(self):
        """Connect to local Cassandra cluster"""
        try:
            print("🔗 Connecting to Cassandra...")
            cluster = Cluster(['localhost'], port=9042)
            self.cassandra_session = cluster.connect()
            
            # Use demo keyspace
            self.cassandra_session.set_keyspace('demo')
            
            # Test query
            result = self.cassandra_session.execute("SELECT COUNT(*) FROM users")
            count = result.one()[0]
            print(f"✅ Connected to Cassandra - {count} existing users")
            self.test_results['cassandra_connection'] = True
            return True
        except Exception as e:
            print(f"❌ Failed to connect to Cassandra: {str(e)}")
            return False

    def connect_to_astra(self):
        """Connect to Astra DB cluster"""
        try:
            print("🔗 Connecting to Astra DB...")
            
            # Load credentials
            with open("migration-cql-demo-token.json") as f:
                secrets = json.load(f)
            
            cloud_config = {
                'secure_connect_bundle': 'secure-connect-migration-cql-demo.zip'
            }
            
            auth_provider = PlainTextAuthProvider(
                secrets["clientId"], 
                secrets["secret"]
            )
            
            cluster = Cluster(
                cloud=cloud_config, 
                auth_provider=auth_provider,
                protocol_version=4
            )
            self.astra_session = cluster.connect()
            
            # Ensure demo keyspace exists
            self.astra_session.execute("""
                CREATE KEYSPACE IF NOT EXISTS demo
                WITH replication = {'class': 'NetworkTopologyStrategy', 'us-east-1': 3}
            """)
            
            self.astra_session.set_keyspace('demo')
            
            # Ensure users table exists
            self.astra_session.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id UUID PRIMARY KEY,
                    name TEXT,
                    email TEXT,
                    gender TEXT,
                    address TEXT
                )
            """)
            
            # Test query
            result = self.astra_session.execute("SELECT COUNT(*) FROM users")
            count = result.one()[0]
            print(f"✅ Connected to Astra DB - {count} existing users")
            self.test_results['astra_connection'] = True
            return True
            
        except Exception as e:
            print(f"❌ Failed to connect to Astra DB: {str(e)}")
            return False

    def perform_dual_write(self):
        """Simulate Phase B dual write operation"""
        if not (self.cassandra_session and self.astra_session):
            print("❌ Cannot perform dual write - missing connections")
            return False

        try:
            # Generate test user data
            user_id = uuid.uuid4()
            user_data = {
                'id': user_id,
                'name': 'Phase B Test User',
                'email': 'phaseb-dual@example.co.uk',
                'gender': 'Other',
                'address': 'ZDM Demo Lane, Dual Write City, DW1 1ZB'
            }

            print(f"📝 Performing dual write for user: {user_data['name']}")
            print(f"   ID: {user_id}")

            # Write to Cassandra (Origin)
            print("   → Writing to Cassandra...")
            self.cassandra_session.execute("""
                INSERT INTO users (id, name, email, gender, address)
                VALUES (?, ?, ?, ?, ?)
            """, (user_data['id'], user_data['name'], user_data['email'], 
                  user_data['gender'], user_data['address']))

            # Write to Astra (Target)  
            print("   → Writing to Astra DB...")
            self.astra_session.execute("""
                INSERT INTO users (id, name, email, gender, address)
                VALUES (?, ?, ?, ?, ?)
            """, (user_data['id'], user_data['name'], user_data['email'],
                  user_data['gender'], user_data['address']))

            print("✅ Dual write completed successfully!")
            self.test_results['dual_write_success'] = True
            return user_id

        except Exception as e:
            print(f"❌ Dual write failed: {str(e)}")
            return False

    def verify_data_consistency(self, user_id):
        """Verify data exists in both databases"""
        try:
            print(f"🔍 Verifying data consistency for user {user_id}...")

            # Check Cassandra
            cassandra_result = self.cassandra_session.execute(
                "SELECT name, email FROM users WHERE id = ?", (user_id,)
            )
            cassandra_row = cassandra_result.one()

            # Check Astra
            astra_result = self.astra_session.execute(
                "SELECT name, email FROM users WHERE id = ?", (user_id,)
            )
            astra_row = astra_result.one()

            if cassandra_row and astra_row:
                if (cassandra_row.name == astra_row.name and 
                    cassandra_row.email == astra_row.email):
                    print("✅ Data consistency verified - records match in both databases")
                    print(f"   Cassandra: {cassandra_row.name} ({cassandra_row.email})")
                    print(f"   Astra DB:  {astra_row.name} ({astra_row.email})")
                    self.test_results['data_consistency'] = True
                    return True
                else:
                    print("❌ Data mismatch between databases")
                    return False
            else:
                print("❌ Data missing in one or both databases")
                print(f"   Cassandra record: {'Found' if cassandra_row else 'Missing'}")
                print(f"   Astra DB record:  {'Found' if astra_row else 'Missing'}")
                return False

        except Exception as e:
            print(f"❌ Data consistency check failed: {str(e)}")
            return False

    def print_summary(self):
        """Print test summary"""
        print("\n" + "="*60)
        print("📊 PHASE B DUAL WRITE TEST SUMMARY")
        print("="*60)
        
        results = [
            ("Cassandra Connection", self.test_results['cassandra_connection']),
            ("Astra DB Connection", self.test_results['astra_connection']),
            ("Dual Write Operation", self.test_results['dual_write_success']),
            ("Data Consistency", self.test_results['data_consistency'])
        ]
        
        for test_name, passed in results:
            status = "✅ PASS" if passed else "❌ FAIL"
            print(f"{test_name:.<40} {status}")
        
        all_passed = all(result for result in self.test_results.values())
        
        print("\n" + "="*60)
        if all_passed:
            print("🎉 ALL PHASE B TESTS PASSED!")
            print("   Dual write capability successfully demonstrated")
        else:
            print("⚠️  SOME TESTS FAILED")
            print("   Check connection and configuration")
        print("="*60)
        
        return all_passed

    def run_test(self):
        """Run complete Phase B dual write test"""
        print("🚀 Starting Phase B Dual Write Test")
        print("="*60)
        
        # Connect to both databases
        cassandra_ok = self.connect_to_cassandra()
        astra_ok = self.connect_to_astra()
        
        if not (cassandra_ok and astra_ok):
            print("\n❌ Cannot proceed - missing database connections")
            self.print_summary()
            return False
        
        # Perform dual write
        user_id = self.perform_dual_write()
        if not user_id:
            self.print_summary()
            return False
        
        # Verify consistency
        self.verify_data_consistency(user_id)
        
        # Print results
        return self.print_summary()

if __name__ == "__main__":
    test = DualWriteTest()
    success = test.run_test()
    sys.exit(0 if success else 1)