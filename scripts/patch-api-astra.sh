#!/bin/bash
# Phase 5: Switch API to Direct Astra DB Connection (No ZDM)
# This script patches the API deployment to connect directly to Astra DB

echo "=== Phase 5: Switching to Direct Astra DB Connection ==="

# Patch the deployment with complete container replacement
kubectl patch deployment python-api --type='strategic' -p='{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "python-api",
            "image": "localhost/python-api:latest",
            "imagePullPolicy": "Never",
            "ports": [
              {"containerPort": 8080}
            ],
            "env": [
              {"name": "CONNECTION_MODE", "value": "astra"},
              {"name": "ASTRA_SECURE_BUNDLE_PATH", "value": "/app/secure-connect.zip"},
              {"name": "ASTRA_CLIENT_ID", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-username"}}},
              {"name": "ASTRA_CLIENT_SECRET", "valueFrom": {"secretKeyRef": {"name": "zdm-proxy-secret", "key": "astra-password"}}},
              {"name": "KEYSPACE", "value": "demo"},
              {"name": "TABLE", "value": "users"}
            ],
            "volumeMounts": [
              {"name": "astra-bundle", "mountPath": "/app", "readOnly": true}
            ],
            "resources": {
              "requests": {"memory": "64Mi", "cpu": "50m"},
              "limits": {"memory": "128Mi", "cpu": "100m"}
            },
            "readinessProbe": {
              "httpGet": {"path": "/", "port": 8080},
              "initialDelaySeconds": 15,
              "periodSeconds": 10
            },
            "livenessProbe": {
              "httpGet": {"path": "/", "port": 8080},
              "initialDelaySeconds": 30,
              "periodSeconds": 15
            }
          }
        ],
        "volumes": [
          {
            "name": "astra-bundle",
            "secret": {
              "secretName": "zdm-proxy-secret",
              "items": [{"key": "secure-connect.zip", "path": "secure-connect.zip"}]
            }
          }
        ]
      }
    }
  }
}'

echo "Waiting for API rollout to complete..."
kubectl rollout status deployment/python-api --timeout=120s

echo "Testing direct Astra DB connection..."
curl -s http://localhost:8080/ | jq .

echo "=== Phase 5 Complete: API now connects directly to Astra DB ==="