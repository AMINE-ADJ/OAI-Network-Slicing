#!/bin/bash
# 2_check_amf.sh - Verify AMF registrations

echo "============================================"
echo "     AMF REGISTRATION CHECK                 "
echo "============================================"
echo ""

# Get AMF pod
AMF_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-amf -o jsonpath="{.items[0].metadata.name}")

if [ -z "$AMF_POD" ]; then
    echo "Error: Could not find AMF pod"
    exit 1
fi

echo "[gNB Registration]"
kubectl logs -n blueprint $AMF_POD 2>&1 | grep -i "gNB" | tail -5
echo ""

echo "[UE Registrations]"
kubectl logs -n blueprint $AMF_POD 2>&1 | grep -E "REGISTERED|Registration" | tail -10
echo ""
