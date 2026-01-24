#!/bin/bash
# 1_check_pods.sh - Verify all pods are running

echo "============================================"
echo "     DEPLOYMENT CHECK - All Pods Status     "
echo "============================================"
echo ""

kubectl get pods -n blueprint

echo ""
echo "Expected: 14 pods all Running (1/1)"
echo ""
