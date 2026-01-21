#!/bin/bash

# start_5g.sh
# One-click script to deploy the 5G network
# ROBUST VERSION: Handles Minikube failures and cleanups automatically.

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info() { echo -e "${BLUE}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }
log_warn() { echo -e "\033[0;33m[WARN] $1${NC}"; }

# Function to check if Minikube is responsive
check_minikube_health() {
    log_info "Checking Minikube API server health..."
    if kubectl get nodes --request-timeout=5s >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to repair Minikube
repair_minikube() {
    log_warn "Minikube appears unresponsive or broken."
    log_info "Attempting to restart Minikube..."
    minikube stop 2>/dev/null || true
    
    # Try simple start first
    if minikube start; then
         log_info "Waiting for API server..."
         sleep 10
         if check_minikube_health; then
            log_success "Minikube recovered!"
            return 0
         fi
    fi

    # If simple start fails, do hard reset
    log_warn "Standard restart failed. Performing HARD RESET (delete & recreate)..."
    minikube delete --all --purge
    # Ensure no zombie processes
    pkill -f "minikube" || true
    
    log_info "Starting fresh Minikube cluster..."
    if minikube start; then
        log_success "Minikube hard reset successful!"
        return 0
    else
        log_error "Failed to start Minikube even after hard reset."
        exit 1
    fi
}

# 1. Minikube Health Check & Repair
if ! check_minikube_health; then
    repair_minikube
else
    log_success "Minikube is healthy."
fi

# 2. Fix Environment
log_info "Refreshing kubectl context..."
minikube update-context
eval $(minikube docker-env)

# 3. Robust Cleanup
log_info "Cleaning up old deployments..."
HELMS=("oai-core" "oai-flexric" "oai-gnb" "oai-nr-ue")
for release in "${HELMS[@]}"; do
    if helm list -n blueprint -q | grep -q "^$release$"; then
        log_info "Uninstalling $release..."
        helm uninstall $release -n blueprint --wait --timeout 1m 2>/dev/null || true
    fi
done

# Force delete namespace if stuck (optional, but safer to just clean resources)
# We avoid deleting the namespace if possible to speed things up, but ensure it's clean.
log_info "Ensuring 'blueprint' namespace exists..."
kubectl create namespace blueprint --dry-run=client -o yaml | kubectl apply -f -

# 4. Wait for Node Readiness (Double Check)
log_info "Verifying Node Readiness..."
kubectl wait --for=condition=Ready node --all --timeout=60s

# 5. Run Ansible Deployment
log_info "Starting Ansible Deployment..."
cd "$SCRIPT_DIR"

# Ensure Ansible Galaxy dependencies if needed (though locally we assume they are there)
# ansible-galaxy collection install -r requirements.yml 2>/dev/null || true

ansible-playbook -i inventories/UTH 5g.yaml --extra-vars "@params.oai-flexric.yaml"

log_success "Deployment commands sent!"

# 6. Wait for MySQL to be ready and add UE IMSI to database
log_info "Waiting for MySQL pod to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=mysql -n blueprint --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=Ready pod -l app=oai-core-mysql -n blueprint --timeout=120s 2>/dev/null || true

# Extract UE IMSI from values file
add_ue_to_database() {
    local UE_VALUES_FILE="$SCRIPT_DIR/bp-flexric/oai-nr-ue/values.yaml"
    
    if [[ ! -f "$UE_VALUES_FILE" ]]; then
        log_warn "UE values file not found at $UE_VALUES_FILE"
        return 1
    fi
    
    # Extract IMSI and keys from values.yaml
    local IMSI=$(grep -E "^\s*fullImsi:" "$UE_VALUES_FILE" | awk '{print $2}' | tr -d '"')
    local KEY=$(grep -E "^\s*fullKey:" "$UE_VALUES_FILE" | awk '{print $2}' | tr -d '"')
    local OPC=$(grep -E "^\s*opc:" "$UE_VALUES_FILE" | awk '{print $2}' | tr -d '"')
    local DNN=$(grep -E "^\s*dnn:" "$UE_VALUES_FILE" | awk '{print $2}' | tr -d '"')
    local SST=$(grep -E "^\s*sst:" "$UE_VALUES_FILE" | awk '{print $2}' | tr -d '"')
    
    if [[ -z "$IMSI" ]]; then
        log_warn "Could not extract IMSI from values file"
        return 1
    fi
    
    log_info "Adding UE IMSI $IMSI to database..."
    
    # Find MySQL pod (pattern: oai-core-mysql-*)
    local MYSQL_POD=$(kubectl get pods -n blueprint --no-headers 2>/dev/null | grep -E 'oai-core-mysql|mysql' | grep -v Terminating | awk '{print $1}' | head -1)
    
    if [[ -z "$MYSQL_POD" ]]; then
        log_warn "MySQL pod not found, skipping database population"
        return 1
    fi
    
    log_info "Found MySQL pod: $MYSQL_POD"
    
    # Generate static IP from IMSI (last 3 digits as IP suffix)
    local IP_SUFFIX=$(echo "$IMSI" | tail -c 4 | sed 's/^0*//')
    [[ -z "$IP_SUFFIX" ]] && IP_SUFFIX="100"
    local STATIC_IP="12.1.1.$IP_SUFFIX"
    
    # Insert into database (using ON DUPLICATE KEY to avoid errors if already exists)
    kubectl exec -i "$MYSQL_POD" -n blueprint -- mysql -uroot -plinux -D oai_db <<EOF
-- Authentication Subscription
INSERT INTO AuthenticationSubscription (ueid, authenticationMethod, encPermanentKey, protectionParameterId, sequenceNumber, authenticationManagementField, algorithmId, encOpcKey, supi) VALUES 
('$IMSI', '5G_AKA', '$KEY', '$KEY', '{"sqn": "000000000020", "sqnScheme": "NON_TIME_BASED", "lastIndexes": {"ausf": 0}}', '8000', 'milenage', '$OPC', '$IMSI')
ON DUPLICATE KEY UPDATE ueid=ueid;

-- Session Management Subscription
INSERT INTO SessionManagementSubscriptionData (ueid, servingPlmnid, singleNssai, dnnConfigurations) VALUES 
('$IMSI', '00101', '{"sst": $SST, "sd": "1"}', '{"$DNN":{"pduSessionTypes":{"defaultSessionType": "IPV4"},"sscModes": {"defaultSscMode": "SSC_MODE_1"},"5gQosProfile": {"5qi": 9,"arp":{"priorityLevel": 8,"preemptCap": "NOT_PREEMPT","preemptVuln":"NOT_PREEMPTABLE"},"priorityLevel":1},"sessionAmbr":{"uplink":"1000Mbps", "downlink":"1000Mbps"},"staticIpAddress":[{"ipv4Addr": "$STATIC_IP"}]}}')
ON DUPLICATE KEY UPDATE ueid=ueid;

-- Access and Mobility Subscription
INSERT INTO AccessAndMobilitySubscriptionData (ueid, servingPlmnid, subscribedUeAmbr, nssai) VALUES
('$IMSI', '00101', '{"uplink":"1000Mbps","downlink":"1000Mbps"}', '{"defaultSingleNssais":[{"sst":$SST,"sd":"1"}],"singleNssais":[]}')
ON DUPLICATE KEY UPDATE ueid=ueid;

SELECT CONCAT('UE ', ueid, ' registered successfully') as Status FROM AuthenticationSubscription WHERE ueid='$IMSI';
EOF

    if [[ $? -eq 0 ]]; then
        log_success "UE IMSI $IMSI added to database (IP: $STATIC_IP)"
    else
        log_warn "Failed to add UE to database"
    fi
}

# Run database population
sleep 5  # Give MySQL time to fully initialize
add_ue_to_database

log_info "Monitor status with: kubectl get pods -n blueprint -w"
