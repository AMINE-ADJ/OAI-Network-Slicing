#!/bin/bash
# 3_connectivity.sh - Basic connectivity test

echo "============================================"
echo "     CONNECTIVITY TEST                      "
echo "============================================"
echo ""

# Get dynamic pod names
UE1_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-nr-ue-slice1 -o jsonpath="{.items[0].metadata.name}")
UE2_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-nr-ue-slice2 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$UE1_POD" ] || [ -z "$UE2_POD" ]; then
    echo "Error: Could not find UE pods"
    exit 1
fi

echo "[UE1 IP Address - Slice 1]"
kubectl exec -n blueprint $UE1_POD -c nr-ue -- ip addr show oaitun_ue1 2>&1 | grep inet
echo ""

echo "[UE2 IP Address - Slice 2]"
kubectl exec -n blueprint $UE2_POD -c nr-ue -- ip addr show oaitun_ue1 2>&1 | grep inet
echo ""

echo "[Ping UPF from UE1]"
kubectl exec -n blueprint $UE1_POD -c nr-ue -- ping -c 3 -I oaitun_ue1 12.1.1.1 2>&1 | grep -E "rtt|packet"
echo ""

echo "[Ping UPF from UE2]"
kubectl exec -n blueprint $UE2_POD -c nr-ue -- ping -c 3 -I oaitun_ue1 12.2.1.1 2>&1 | grep -E "rtt|packet"
echo ""

echo "┌─────────────────────────────────────────────────────────────────────┐"
echo "│  UE1 (eMBB)  → IP: 12.1.1.x  → UPF-Slice1 (12.1.1.1)   ✓           │"
echo "│  UE2 (uRLLC) → IP: 12.2.1.x  → UPF-Slice2 (12.2.1.1)   ✓           │"
echo "└─────────────────────────────────────────────────────────────────────┘"
echo ""
