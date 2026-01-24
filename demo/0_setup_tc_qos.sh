#!/bin/bash
# setup_tc_qos.sh - Apply traffic control rules to simulate QoS differences
# 
# This script applies tc (traffic control) rules on UPF pods to demonstrate
# visible QoS differentiation between slices:
#   - eMBB (Slice 1): Higher bandwidth, moderate latency (like video streaming)
#   - uRLLC (Slice 2): Lower bandwidth, ultra-low latency (like robotics)

echo "============================================"
echo "     APPLYING TC QOS RULES                  "
echo "============================================"
echo ""

# Get dynamic UPF pod names
UPF1_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-upf-slice1 -o jsonpath="{.items[0].metadata.name}")
UPF2_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-upf-slice2 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$UPF1_POD" ] || [ -z "$UPF2_POD" ]; then
    echo "Error: Could not find UPF pods"
    exit 1
fi

echo "[Installing iproute2 on UPFs (for tc command)...]"
kubectl exec -n blueprint $UPF1_POD -- apt-get update -qq 2>/dev/null
kubectl exec -n blueprint $UPF1_POD -- apt-get install -y -qq iproute2 2>/dev/null
kubectl exec -n blueprint $UPF2_POD -- apt-get update -qq 2>/dev/null
kubectl exec -n blueprint $UPF2_POD -- apt-get install -y -qq iproute2 2>/dev/null
echo ""

echo "[Clearing existing tc rules...]"
kubectl exec -n blueprint $UPF1_POD -- tc qdisc del dev tun0 root 2>/dev/null || true
kubectl exec -n blueprint $UPF2_POD -- tc qdisc del dev tun0 root 2>/dev/null || true
echo ""

# ============================================================
# SLICE 1 (eMBB): High bandwidth, moderate latency
# - Rate: 10 Mbps
# - Latency: 20ms (typical for streaming)
# ============================================================
echo "[Applying eMBB QoS on UPF-Slice1...]"
echo "  → Rate: 10 Mbps, Latency: 20ms"
kubectl exec -n blueprint $UPF1_POD -- tc qdisc add dev tun0 root netem delay 20ms rate 10mbit
echo ""

# ============================================================
# SLICE 2 (uRLLC): Lower bandwidth, ultra-low latency
# - Rate: 5 Mbps
# - Latency: 2ms (ultra-low for robotics/gaming)
# ============================================================
echo "[Applying uRLLC QoS on UPF-Slice2...]"
echo "  → Rate: 5 Mbps, Latency: 2ms"
kubectl exec -n blueprint $UPF2_POD -- tc qdisc add dev tun0 root netem delay 2ms rate 5mbit
echo ""

echo "============================================"
echo "     TC QOS RULES APPLIED                   "
echo "============================================"
echo ""
echo "┌─────────────────────────────────────────────────────────────────────┐"
echo "│                     QOS CONFIGURATION                              │"
echo "├─────────────────────────────────────────────────────────────────────┤"
echo "│  Slice 1 (eMBB):   Rate=10Mbps    Latency=20ms   (streaming)       │"
echo "│  Slice 2 (uRLLC):  Rate=5Mbps     Latency=2ms    (low-latency)     │"
echo "├─────────────────────────────────────────────────────────────────────┤"
echo ""
