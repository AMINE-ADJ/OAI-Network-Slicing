#!/bin/bash
# clear_tc_qos.sh - Remove all tc rules

echo "============================================"
echo "     REMOVING TC QOS RULES                  "
echo "============================================"
echo ""

# Get dynamic UPF pod names
UPF1_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-upf-slice1 -o jsonpath="{.items[0].metadata.name}")
UPF2_POD=$(kubectl get pods -n blueprint -l app.kubernetes.io/name=oai-upf-slice2 -o jsonpath="{.items[0].metadata.name}")

if [ -z "$UPF1_POD" ] || [ -z "$UPF2_POD" ]; then
    echo "Error: Could not find UPF pods"
    exit 1
fi

echo "[Clearing tc rules on UPF-Slice1...]"
kubectl exec -n blueprint $UPF1_POD -- tc qdisc del dev tun0 root 2>/dev/null || true
echo "  Done."

echo "[Clearing tc rules on UPF-Slice2...]"
kubectl exec -n blueprint $UPF2_POD -- tc qdisc del dev tun0 root 2>/dev/null || true
echo "  Done."

echo ""
echo "All tc rules removed. Network back to default."
echo ""
