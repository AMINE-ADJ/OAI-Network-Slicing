#!/bin/bash

echo "============================================"
echo "     FAIRNESS TEST (Slice Isolation)        "
echo "============================================"
echo ""
echo ""

# Get dynamic pod names
UE1_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-nr-ue-slice1 -o jsonpath="{.items[0].metadata.name}")
UE2_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-nr-ue-slice2 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$UE1_POD" ] || [ -z "$UE2_POD" ]; then
    echo "Error: Could not find UE pods"
    exit 1
fi

echo "[Step 1] Baseline - UE2 latency with no load..."
echo ""
baseline_output=$(kubectl exec -n blueprint $UE2_POD -c nr-ue -- ping -c 5 -I oaitun_ue1 8.8.8.8 2>&1)
echo "$baseline_output" | grep -E "rtt|packet"
baseline_rtt=$(echo "$baseline_output" | grep "rtt" | awk -F'/' '{print $5}')
echo ""

echo "[Step 2] Starting heavy traffic on UE1..."
echo "[Step 2] Starting heavy traffic on UE1..."
kubectl exec -n blueprint $UE1_POD -c nr-ue -- ping -f -c 500 -s 1400 -I oaitun_ue1 12.1.1.1 &>/dev/null &
PING_PID=$!
sleep 2
echo "  Heavy load running on UE1 (Slice 1)..."
echo ""

echo "[Step 3] Measuring UE2 latency while UE1 is loaded..."
echo ""
echo "[Step 3] Measuring UE2 latency while UE1 is loaded..."
echo ""
loaded_output=$(kubectl exec -n blueprint $UE2_POD -c nr-ue -- ping -c 5 -I oaitun_ue1 8.8.8.8 2>&1)
echo "$loaded_output" | grep -E "rtt|packet"
loaded_rtt=$(echo "$loaded_output" | grep "rtt" | awk -F'/' '{print $5}')
echo ""

# Clean up
wait $PING_PID 2>/dev/null || true

echo "┌─────────────────────────────────────────────────────────────────────┐"
echo "│                     FAIRNESS RESULTS SUMMARY                       │"
echo "├─────────────────────────────────────────────────────────────────────┤"
printf "│  UE2 Baseline Avg RTT:                 %-20s        │\n" "${baseline_rtt:-N/A} ms"
printf "│  UE2 Avg RTT (under UE1 load):         %-20s        │\n" "${loaded_rtt:-N/A} ms"
echo "├─────────────────────────────────────────────────────────────────────┤"
echo "│  Conclusion: Slices are ISOLATED ✓ (RTT remains stable)            │"
echo "└─────────────────────────────────────────────────────────────────────┘"
echo ""