#!/usr/bin/env python3
"""
FastAPI service for Cassandra 5 ZDM Demo
Provides REST API for data operations during migration
"""

import os
import uuid
from typing import Optional, List
from datetime import datetime

from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel, Field
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from cassandra.policies import DCAwareRoundRobinPolicy
import uvicorn

# Configuration
CASSANDRA_HOST = os.getenv('CASSANDRA_HOST', 'localhost')
CASSANDRA_PORT = int(os.getenv('CASSANDRA_PORT', '9042'))
CASSANDRA_USERNAME = os.getenv('CASSANDRA_USERNAME', 'cassandra')
CASSANDRA_PASSWORD = os.getenv('CASSANDRA_PASSWORD', 'cassandra')
KEYSPACE = os.getenv('KEYSPACE', 'demo')
TABLE = os.getenv('TABLE', 'users')

# Pydantic models
class User(BaseModel):
    id: Optional[str] = Field(default_factory=lambda: str(uuid.uuid4()))
    name: str = Field(..., min_length=1, max_length=100)
    email: str = Field(..., pattern=r'^[^@]+@[^@]+\.[^@]+$')
    gender: str = Field(..., pattern=r'^(Male|Female|Non-binary|Prefer not to say)$')
    address: str = Field(..., min_length=1, max_length=500)

class UserResponse(User):
    created_at: Optional[datetime] = None

class CreateUserRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    email: str = Field(..., pattern=r'^[^@]+@[^@]+\.[^@]+$')
    gender: str = Field(..., pattern=r'^(Male|Female|Non-binary|Prefer not to say)$')
    address: str = Field(..., min_length=1, max_length=500)

# FastAPI app
app = FastAPI(
    title="Cassandra 5 ZDM Demo API",
    description="REST API for demonstrating Zero Downtime Migration from Cassandra to Astra DB",
    version="1.0.0"
)

# Global connection
cluster = None
session = None

def get_cassandra_session():
    """Get Cassandra session - NO FALLBACK, fails if configured endpoint unavailable"""
    global cluster, session
    
    if session is None:
        auth_provider = PlainTextAuthProvider(
            username=CASSANDRA_USERNAME,
            password=CASSANDRA_PASSWORD
        )
        
        print(f"Attempting connection to {CASSANDRA_HOST}:{CASSANDRA_PORT}")
        
        try:
            cluster = Cluster(
                [CASSANDRA_HOST],
                port=CASSANDRA_PORT,
                auth_provider=auth_provider,
                load_balancing_policy=DCAwareRoundRobinPolicy(),
                connect_timeout=10
            )
            
            session = cluster.connect(KEYSPACE)
            print(f"Successfully connected to {CASSANDRA_HOST}:{CASSANDRA_PORT}")
            
        except Exception as e:
            print(f"Failed to connect to {CASSANDRA_HOST}:{CASSANDRA_PORT}: {e}")
            if cluster:
                cluster.shutdown()
                cluster = None
            raise Exception(f"Connection failed to {CASSANDRA_HOST}:{CASSANDRA_PORT} - No fallback available")
        
        # Prepare statements
        session.execute(f"""
            CREATE TABLE IF NOT EXISTS {TABLE} (
                id UUID PRIMARY KEY,
                name TEXT,
                email TEXT,
                gender TEXT,
                address TEXT,
                created_at TIMESTAMP
            )
        """)
    
    return session

@app.on_event("startup")
async def startup_event():
    """Initialize database connection on startup"""
    try:
        get_cassandra_session()
        print(f"Connected to Cassandra at {CASSANDRA_HOST}:{CASSANDRA_PORT}")
        print(f"Using keyspace: {KEYSPACE}")
    except Exception as e:
        print(f"Failed to connect to Cassandra: {e}")
        raise

@app.on_event("shutdown")
async def shutdown_event():
    """Clean up connections on shutdown"""
    global cluster
    if cluster:
        cluster.shutdown()

@app.get("/")
async def root():
    """Health check endpoint"""
    connection_type = "Direct Cassandra"
    if CASSANDRA_HOST == "zdm-proxy-svc":
        connection_type = "ZDM Proxy (Phase B Dual Write)"
    
    return {
        "service": "Cassandra 5 ZDM Demo API",
        "status": "healthy",
        "connection_type": connection_type,
        "target": f"{CASSANDRA_HOST}:{CASSANDRA_PORT}",
        "keyspace": KEYSPACE
    }

@app.get("/users", response_model=List[UserResponse])
async def get_users(limit: int = 10, session=Depends(get_cassandra_session)):
    """Get list of users"""
    try:
        query = f"SELECT id, name, email, gender, address FROM {TABLE} LIMIT %s"
        result = session.execute(query, (limit,))
        
        users = []
        for row in result:
            users.append(UserResponse(
                id=str(row.id),
                name=row.name,
                email=row.email,
                gender=row.gender,
                address=row.address,
                created_at=None
            ))
        
        return users
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch users: {str(e)}")

@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: str, session=Depends(get_cassandra_session)):
    """Get a specific user by ID"""
    try:
        user_uuid = uuid.UUID(user_id)
        query = f"SELECT id, name, email, gender, address FROM {TABLE} WHERE id = %s"
        result = session.execute(query, (user_uuid,))
        row = result.one()
        
        if not row:
            raise HTTPException(status_code=404, detail="User not found")
        
        return UserResponse(
            id=str(row.id),
            name=row.name,
            email=row.email,
            gender=row.gender,
            address=row.address,
            created_at=None
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid user ID format")
    except Exception as e:
        if "No rows returned" in str(e):
            raise HTTPException(status_code=404, detail="User not found")
        raise HTTPException(status_code=500, detail=f"Failed to fetch user: {str(e)}")

@app.post("/users", response_model=UserResponse)
async def create_user(user_data: CreateUserRequest, session=Depends(get_cassandra_session)):
    """Create a new user"""
    try:
        user_id = uuid.uuid4()
        created_at = datetime.utcnow()
        
        insert_query = f"""
            INSERT INTO {TABLE} (id, name, email, gender, address)
            VALUES (%s, %s, %s, %s, %s)
        """
        
        session.execute(insert_query, (
            user_id,
            user_data.name,
            user_data.email,
            user_data.gender,
            user_data.address
        ))
        
        return UserResponse(
            id=str(user_id),
            name=user_data.name,
            email=user_data.email,
            gender=user_data.gender,
            address=user_data.address,
            created_at=None
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create user: {str(e)}")

@app.delete("/users/{user_id}")
async def delete_user(user_id: str, session=Depends(get_cassandra_session)):
    """Delete a user by ID"""
    try:
        user_uuid = uuid.UUID(user_id)
        
        # Check if user exists first
        check_query = f"SELECT id FROM {TABLE} WHERE id = %s"
        result = session.execute(check_query, (user_uuid,))
        if not result.one():
            raise HTTPException(status_code=404, detail="User not found")
        
        # Delete the user
        delete_query = f"DELETE FROM {TABLE} WHERE id = %s"
        session.execute(delete_query, (user_uuid,))
        
        return {"message": f"User {user_id} deleted successfully"}
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid user ID format")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete user: {str(e)}")

@app.get("/stats")
async def get_stats(session=Depends(get_cassandra_session)):
    """Get database statistics"""
    try:
        count_query = f"SELECT COUNT(*) FROM {TABLE}"
        result = session.execute(count_query)
        total_users = result.one()[0]
        
        connection_info = {
            "host": CASSANDRA_HOST,
            "port": CASSANDRA_PORT,
            "via_zdm_proxy": CASSANDRA_HOST == "zdm-proxy-svc"
        }
        
        return {
            "total_users": total_users,
            "keyspace": KEYSPACE,
            "table": TABLE,
            "connection": connection_info,
            "routing_status": "API routed through ZDM proxy" if CASSANDRA_HOST == "zdm-proxy-svc" else "Direct Cassandra connection"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get stats: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8080,
        reload=True,
        log_level="info"
    )