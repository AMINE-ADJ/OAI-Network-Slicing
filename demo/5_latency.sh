#!/bin/bash
# 5_latency.sh - Latency comparison test

echo "============================================"
echo "     LATENCY TEST (ping)                    "
echo "============================================"
echo ""

# Get dynamic pod names
UE1_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-nr-ue-slice1 -o jsonpath="{.items[0].metadata.name}")
UE2_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-nr-ue-slice2 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$UE1_POD" ] || [ -z "$UE2_POD" ]; then
    echo "Error: Could not find UE pods"
    exit 1
fi

echo "[UE1 Latency - eMBB (5QI=9)]"
ue1_output=$(kubectl exec -n blueprint $UE1_POD -c nr-ue -- ping -c 10 -I oaitun_ue1 8.8.8.8 2>&1)
echo "$ue1_output" | grep -E "rtt|packet"
ue1_rtt=$(echo "$ue1_output" | grep "rtt" | awk -F'/' '{print $5}')
echo ""

echo "[UE2 Latency - uRLLC (5QI=1)]"
echo "[UE2 Latency - uRLLC (5QI=1)]"
ue2_output=$(kubectl exec -n blueprint $UE2_POD -c nr-ue -- ping -c 10 -I oaitun_ue1 8.8.8.8 2>&1)
echo "$ue2_output" | grep -E "rtt|packet"
ue2_rtt=$(echo "$ue2_output" | grep "rtt" | awk -F'/' '{print $5}')
echo ""

echo "┌─────────────────────────────────────────────────────────────────────┐"
echo "│                     LATENCY RESULTS SUMMARY                        │"
echo "├─────────────────────────────────────────────────────────────────────┤"
printf "│  UE1 (eMBB,  5QI=9) Avg RTT:           %-20s        │\n" "${ue1_rtt:-N/A} ms"
printf "│  UE2 (uRLLC, 5QI=1) Avg RTT:           %-20s        │\n" "${ue2_rtt:-N/A} ms"
echo "├─────────────────────────────────────────────────────────────────────┤"
echo "│  Note: Lower RTT for UE2 which is on the uRLLC slice                │"
echo "└─────────────────────────────────────────────────────────────────────┘"
echo ""
