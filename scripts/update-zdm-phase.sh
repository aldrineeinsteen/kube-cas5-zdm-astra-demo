#!/bin/bash
# ZDM Phase Management Script
# Usage: ./update-zdm-phase.sh [A|B|C]

set -e

PHASE=${1:-A}
NAMESPACE=${2:-default}

if [[ ! "$PHASE" =~ ^[ABC]$ ]]; then
    echo "Error: Phase must be A, B, or C"
    echo "Usage: $0 [A|B|C] [namespace]"
    echo ""
    echo "Phases:"
    echo "  A: Writes only to source Cassandra"
    echo "  B: Dual writes to both source and Astra"
    echo "  C: Cutover - all traffic to Astra"
    exit 1
fi

echo "Updating ZDM proxy to Phase $PHASE..."

# Update the deployment environment variable
kubectl patch deployment zdm-proxy -n "$NAMESPACE" -p="{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"zdm-proxy\",\"env\":[{\"name\":\"ZDM_PHASE\",\"value\":\"$PHASE\"}]}]}}}}"

# Wait for rollout to complete
kubectl rollout status deployment/zdm-proxy -n "$NAMESPACE" --timeout=300s

echo "✅ ZDM proxy updated to Phase $PHASE successfully!"

# Show current status
echo ""
echo "Current ZDM proxy status:"
kubectl get pods -l app=zdm-proxy -n "$NAMESPACE"
echo ""
echo "Phase configuration:"
case $PHASE in
    A) echo "  📝 Phase A: Direct writes to source Cassandra only" ;;
    B) echo "  🔄 Phase B: Dual writes through ZDM proxy to both clusters" ;;
    C) echo "  🎯 Phase C: Cutover - all traffic routed to Astra DB" ;;
esac