#!/usr/bin/env python3
"""
Data Consistency Validator for Phase B ZDM Implementation
Validates data consistency between Cassandra (origin) and Astra DB (target)
"""
import sys
import os
import json
import uuid
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass

@dataclass
class ConsistencyResult:
    """Data consistency check result"""
    record_id: str
    cassandra_exists: bool
    astra_exists: bool
    data_matches: bool
    differences: List[str]
    timestamp: datetime

@dataclass
class ValidationSummary:
    """Summary of validation results"""
    total_records: int
    consistent_records: int
    missing_in_cassandra: int
    missing_in_astra: int
    data_mismatches: int
    consistency_rate: float
    validation_time: float

class DataConsistencyValidator:
    """
    Validates data consistency between Cassandra and Astra DB
    for Phase B dual write implementation
    """
    
    def __init__(self):
        self.validation_results = []
        self.summary = None
        
    def simulate_cassandra_query(self, query: str, params: tuple = None) -> List[Dict]:
        """Simulate Cassandra query execution"""
        # In real implementation, this would execute against Cassandra
        if "SELECT * FROM users" in query:
            return [
                {
                    'id': uuid.UUID('550e8400-e29b-41d4-a716-446655440000'),
                    'name': 'Test User 1',
                    'email': 'test1@example.com',
                    'gender': 'Male',
                    'address': '123 Test Street'
                },
                {
                    'id': uuid.UUID('550e8400-e29b-41d4-a716-446655440001'),
                    'name': 'Test User 2',
                    'email': 'test2@example.com',
                    'gender': 'Female',
                    'address': '456 Test Avenue'
                }
            ]
        elif "WHERE id = ?" in query and params:
            # Simulate record lookup
            test_records = {
                uuid.UUID('550e8400-e29b-41d4-a716-446655440000'): {
                    'id': uuid.UUID('550e8400-e29b-41d4-a716-446655440000'),
                    'name': 'Test User 1',
                    'email': 'test1@example.com',
                    'gender': 'Male',
                    'address': '123 Test Street'
                }
            }
            record = test_records.get(params[0])
            return [record] if record else []
        else:
            return []
    
    def simulate_astra_query(self, query: str, params: tuple = None) -> List[Dict]:
        """Simulate Astra DB query execution"""
        # In real implementation, this would execute against Astra DB
        if "SELECT * FROM users" in query:
            return [
                {
                    'id': uuid.UUID('550e8400-e29b-41d4-a716-446655440000'),
                    'name': 'Test User 1',
                    'email': 'test1@example.com',
                    'gender': 'Male',
                    'address': '123 Test Street'
                },
                {
                    'id': uuid.UUID('550e8400-e29b-41d4-a716-446655440001'),
                    'name': 'Test User 2 Updated',  # Simulate data difference
                    'email': 'test2@example.com',
                    'gender': 'Female',
                    'address': '456 Test Avenue'
                }
            ]
        elif "WHERE id = ?" in query and params:
            # Simulate record lookup
            test_records = {
                uuid.UUID('550e8400-e29b-41d4-a716-446655440000'): {
                    'id': uuid.UUID('550e8400-e29b-41d4-a716-446655440000'),
                    'name': 'Test User 1',
                    'email': 'test1@example.com',
                    'gender': 'Male',
                    'address': '123 Test Street'
                }
            }
            record = test_records.get(params[0])
            return [record] if record else []
        else:
            return []
    
    def validate_record_consistency(self, record_id: uuid.UUID) -> ConsistencyResult:
        """Validate consistency for a specific record"""
        print(f"   🔍 Validating record: {record_id}")
        
        # Query Cassandra
        cassandra_records = self.simulate_cassandra_query(
            "SELECT * FROM users WHERE id = ?", (record_id,)
        )
        cassandra_record = cassandra_records[0] if cassandra_records else None
        
        # Query Astra DB
        astra_records = self.simulate_astra_query(
            "SELECT * FROM users WHERE id = ?", (record_id,)
        )
        astra_record = astra_records[0] if astra_records else None
        
        # Check existence
        cassandra_exists = cassandra_record is not None
        astra_exists = astra_record is not None
        
        # Check data consistency
        differences = []
        data_matches = False
        
        if cassandra_exists and astra_exists:
            data_matches = True
            for field in ['name', 'email', 'gender', 'address']:
                cassandra_value = cassandra_record.get(field)
                astra_value = astra_record.get(field)
                
                if cassandra_value != astra_value:
                    differences.append(
                        f"{field}: Cassandra='{cassandra_value}' vs Astra='{astra_value}'"
                    )
                    data_matches = False
        
        result = ConsistencyResult(
            record_id=str(record_id),
            cassandra_exists=cassandra_exists,
            astra_exists=astra_exists,
            data_matches=data_matches,
            differences=differences,
            timestamp=datetime.now()
        )
        
        # Print result
        if cassandra_exists and astra_exists:
            if data_matches:
                print(f"     ✅ Record consistent")
            else:
                print(f"     ⚠️  Data mismatch detected:")
                for diff in differences:
                    print(f"       - {diff}")
        elif not cassandra_exists:
            print(f"     ❌ Record missing in Cassandra")
        elif not astra_exists:
            print(f"     ❌ Record missing in Astra DB")
        
        return result
    
    def validate_full_dataset(self) -> ValidationSummary:
        """Validate consistency across entire dataset"""
        print("🔍 Starting full dataset validation...")
        start_time = time.time()
        
        # Get all records from both databases
        cassandra_records = self.simulate_cassandra_query("SELECT * FROM users")
        astra_records = self.simulate_astra_query("SELECT * FROM users")
        
        # Create sets of record IDs
        cassandra_ids = {record['id'] for record in cassandra_records}
        astra_ids = {record['id'] for record in astra_records}
        all_ids = cassandra_ids.union(astra_ids)
        
        print(f"   Found {len(cassandra_ids)} records in Cassandra")
        print(f"   Found {len(astra_ids)} records in Astra DB")
        print(f"   Total unique records: {len(all_ids)}")
        
        # Validate each record
        self.validation_results = []
        for record_id in all_ids:
            result = self.validate_record_consistency(record_id)
            self.validation_results.append(result)
        
        # Calculate summary statistics
        end_time = time.time()
        validation_time = end_time - start_time
        
        consistent_records = sum(1 for r in self.validation_results if r.data_matches)
        missing_in_cassandra = sum(1 for r in self.validation_results if not r.cassandra_exists)
        missing_in_astra = sum(1 for r in self.validation_results if not r.astra_exists)
        data_mismatches = sum(1 for r in self.validation_results 
                            if r.cassandra_exists and r.astra_exists and not r.data_matches)
        
        consistency_rate = (consistent_records / len(all_ids)) * 100 if all_ids else 0
        
        self.summary = ValidationSummary(
            total_records=len(all_ids),
            consistent_records=consistent_records,
            missing_in_cassandra=missing_in_cassandra,
            missing_in_astra=missing_in_astra,
            data_mismatches=data_mismatches,
            consistency_rate=consistency_rate,
            validation_time=validation_time
        )
        
        return self.summary
    
    def validate_sample_records(self, sample_size: int = 10) -> ValidationSummary:
        """Validate consistency for a sample of records"""
        print(f"🔍 Starting sample validation ({sample_size} records)...")
        start_time = time.time()
        
        # Generate sample record IDs (in real implementation, would query database)
        sample_ids = [
            uuid.UUID('550e8400-e29b-41d4-a716-446655440000'),
            uuid.UUID('550e8400-e29b-41d4-a716-446655440001'),
        ]
        
        print(f"   Validating {len(sample_ids)} sample records")
        
        # Validate each record
        self.validation_results = []
        for record_id in sample_ids:
            result = self.validate_record_consistency(record_id)
            self.validation_results.append(result)
        
        # Calculate summary
        end_time = time.time()
        validation_time = end_time - start_time
        
        consistent_records = sum(1 for r in self.validation_results if r.data_matches)
        missing_in_cassandra = sum(1 for r in self.validation_results if not r.cassandra_exists)
        missing_in_astra = sum(1 for r in self.validation_results if not r.astra_exists)
        data_mismatches = sum(1 for r in self.validation_results 
                            if r.cassandra_exists and r.astra_exists and not r.data_matches)
        
        consistency_rate = (consistent_records / len(sample_ids)) * 100 if sample_ids else 0
        
        self.summary = ValidationSummary(
            total_records=len(sample_ids),
            consistent_records=consistent_records,
            missing_in_cassandra=missing_in_cassandra,
            missing_in_astra=missing_in_astra,
            data_mismatches=data_mismatches,
            consistency_rate=consistency_rate,
            validation_time=validation_time
        )
        
        return self.summary
    
    def generate_reconciliation_report(self) -> str:
        """Generate a detailed reconciliation report"""
        if not self.validation_results:
            return "No validation results available. Run validation first."
        
        report = []
        report.append("="*80)
        report.append("DATA CONSISTENCY RECONCILIATION REPORT")
        report.append("="*80)
        report.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append(f"Validation Duration: {self.summary.validation_time:.2f} seconds")
        report.append("")
        
        # Summary statistics
        report.append("SUMMARY STATISTICS:")
        report.append(f"  Total Records Validated: {self.summary.total_records}")
        report.append(f"  Consistent Records: {self.summary.consistent_records}")
        report.append(f"  Missing in Cassandra: {self.summary.missing_in_cassandra}")
        report.append(f"  Missing in Astra DB: {self.summary.missing_in_astra}")
        report.append(f"  Data Mismatches: {self.summary.data_mismatches}")
        report.append(f"  Consistency Rate: {self.summary.consistency_rate:.1f}%")
        report.append("")
        
        # Detailed findings
        if self.summary.missing_in_cassandra > 0:
            report.append("RECORDS MISSING IN CASSANDRA:")
            for result in self.validation_results:
                if not result.cassandra_exists:
                    report.append(f"  - {result.record_id}")
            report.append("")
        
        if self.summary.missing_in_astra > 0:
            report.append("RECORDS MISSING IN ASTRA DB:")
            for result in self.validation_results:
                if not result.astra_exists:
                    report.append(f"  - {result.record_id}")
            report.append("")
        
        if self.summary.data_mismatches > 0:
            report.append("DATA MISMATCHES:")
            for result in self.validation_results:
                if result.cassandra_exists and result.astra_exists and not result.data_matches:
                    report.append(f"  Record: {result.record_id}")
                    for diff in result.differences:
                        report.append(f"    - {diff}")
            report.append("")
        
        # Recommendations
        report.append("RECOMMENDATIONS:")
        if self.summary.consistency_rate >= 95:
            report.append("  ✅ Data consistency is excellent (≥95%)")
            report.append("  → Safe to proceed to Phase C")
        elif self.summary.consistency_rate >= 90:
            report.append("  ⚠️  Data consistency is good (≥90%)")
            report.append("  → Address minor inconsistencies before Phase C")
        else:
            report.append("  ❌ Data consistency below acceptable threshold (<90%)")
            report.append("  → Investigate and resolve consistency issues")
            report.append("  → Re-run validation before proceeding")
        
        report.append("")
        report.append("="*80)
        
        return "\n".join(report)
    
    def print_validation_summary(self):
        """Print validation summary to console"""
        if not self.summary:
            print("No validation summary available")
            return
        
        print("\n" + "="*80)
        print("📊 DATA CONSISTENCY VALIDATION SUMMARY")
        print("="*80)
        
        print(f"⏱️  Validation Time: {self.summary.validation_time:.2f} seconds")
        print(f"📊 Total Records: {self.summary.total_records}")
        print()
        
        print("📈 Consistency Metrics:")
        print(f"   Consistent Records: {self.summary.consistent_records}")
        print(f"   Missing in Cassandra: {self.summary.missing_in_cassandra}")
        print(f"   Missing in Astra DB: {self.summary.missing_in_astra}")
        print(f"   Data Mismatches: {self.summary.data_mismatches}")
        print()
        
        print(f"🎯 Consistency Rate: {self.summary.consistency_rate:.1f}%")
        
        # Status indicator
        if self.summary.consistency_rate >= 95:
            print("✅ EXCELLENT - Ready for Phase C")
        elif self.summary.consistency_rate >= 90:
            print("⚠️  GOOD - Minor inconsistencies detected")
        else:
            print("❌ POOR - Significant inconsistencies detected")
        
        print("="*80)

def main():
    """Main validation execution"""
    print("🎯 Phase B Data Consistency Validator")
    print("Validating data consistency between Cassandra and Astra DB")
    print()
    
    validator = DataConsistencyValidator()
    
    try:
        # Run sample validation (faster for demo)
        print("Running sample validation...")
        summary = validator.validate_sample_records(sample_size=10)
        
        # Print results
        validator.print_validation_summary()
        
        # Generate reconciliation report
        report = validator.generate_reconciliation_report()
        
        # Save report to file
        report_filename = f"consistency_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        with open(report_filename, 'w') as f:
            f.write(report)
        
        print(f"\n📄 Detailed report saved to: {report_filename}")
        
        # Return success based on consistency rate
        return summary.consistency_rate >= 90
        
    except Exception as e:
        print(f"\n❌ Validation failed: {str(e)}")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)