#!/bin/bash

# ============================================================
# Cleanup Script for 5G Network Slicing Deployment
# ============================================================
# This script cleans up the minikube cluster to allow fresh deployment
# Usage: ./cleanup_cluster.sh [--hard]
#   --hard : Also restarts minikube completely
# ============================================================

set -e

NAMESPACE="blueprint"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check minikube status
check_minikube() {
    log_info "Checking minikube status..."
    if ! minikube status &>/dev/null; then
        log_warning "Minikube is not running or not healthy"
        return 1
    fi
    log_success "Minikube is running"
    return 0
}

# Start minikube if needed
start_minikube() {
    log_info "Starting minikube..."
    minikube start --force
    log_info "Waiting for API server..."
    sleep 10
    minikube update-context
    kubectl wait --for=condition=Ready node --all --timeout=120s
    log_success "Minikube is ready"
}

# Uninstall all helm releases in namespace
cleanup_helm_releases() {
    log_info "Listing helm releases in namespace '$NAMESPACE'..."
    
    releases=$(helm list -n $NAMESPACE -q 2>/dev/null || echo "")
    
    if [ -z "$releases" ]; then
        log_info "No helm releases found in namespace '$NAMESPACE'"
        return
    fi
    
    echo "Found releases: $releases"
    
    for release in $releases; do
        log_info "Uninstalling $release..."
        helm uninstall "$release" -n $NAMESPACE --wait --timeout 60s 2>/dev/null || \
            log_warning "Failed to uninstall $release (may already be gone)"
    done
    
    log_success "All helm releases uninstalled"
}

# Delete stuck pods
cleanup_pods() {
    log_info "Force deleting any remaining pods in '$NAMESPACE'..."
    
    kubectl delete pods --all -n $NAMESPACE --force --grace-period=0 2>/dev/null || true
    
    log_success "Pods cleaned up"
}

# Delete PVCs
cleanup_pvcs() {
    log_info "Deleting PVCs in '$NAMESPACE'..."
    kubectl delete pvc --all -n $NAMESPACE 2>/dev/null || true
    log_success "PVCs cleaned up"
}

# Delete namespace (optional)
cleanup_namespace() {
    log_info "Deleting namespace '$NAMESPACE'..."
    kubectl delete namespace $NAMESPACE --timeout=60s 2>/dev/null || true
    log_success "Namespace deleted"
}

# Hard reset - restart minikube completely
hard_reset() {
    log_warning "Performing HARD RESET - this will restart minikube completely"
    
    log_info "Stopping minikube..."
    minikube stop 2>/dev/null || true
    
    log_info "Deleting minikube..."
    minikube delete --all --purge 2>/dev/null || true
    
    log_info "Starting fresh minikube cluster..."
    minikube start
    
    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready node --all --timeout=120s
    
    log_success "Fresh minikube cluster is ready!"
}

# Prune docker to free space
prune_docker() {
    log_info "Pruning Docker to free disk space..."
    docker system prune -f 2>/dev/null || true
    minikube ssh -- docker system prune -f 2>/dev/null || true
    log_success "Docker pruned"
}

# Main
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       5G Network Slicing - Cluster Cleanup Script            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ "$1" == "--hard" ]; then
        log_warning "Hard reset requested"
        hard_reset
        exit 0
    fi
    
    # Check if minikube is running
    if ! check_minikube; then
        log_info "Attempting to start minikube..."
        start_minikube
    fi
    
    # Prune docker first if space is low
    prune_docker
    
    # Clean up in order
    cleanup_helm_releases
    cleanup_pods
    cleanup_pvcs
    
    # Recreate namespace
    log_info "Recreating namespace '$NAMESPACE'..."
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    echo ""
    log_success "Cleanup complete! Cluster is ready for fresh deployment."
    echo ""
    echo "To deploy the 5G network with slicing, run:"
    echo "  ./bp-flexric-slicing/start_slicing.sh deploy"
    echo ""
}

main "$@"
