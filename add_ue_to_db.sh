#!/bin/bash

# add_ue_to_db.sh
# Add a UE subscriber to the OAI 5G Core MySQL database
# Usage: ./add_ue_to_db.sh [IMSI] [KEY] [OPC] [DNN] [SST]
#        ./add_ue_to_db.sh                     # Uses values from bp-flexric/oai-nr-ue/values.yaml
#        ./add_ue_to_db.sh 001010000000101     # Custom IMSI with default keys

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-blueprint}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Default values (OAI test SIM)
DEFAULT_KEY="fec86ba6eb707ed08905757b1bb44b8f"
DEFAULT_OPC="C42449363BBAD02B66D16BC975D77CC1"
DEFAULT_DNN="oai"
DEFAULT_SST="1"

# Try to extract from values.yaml if no args provided
extract_from_values() {
    local UE_VALUES_FILE="$SCRIPT_DIR/bp-flexric/oai-nr-ue/values.yaml"
    
    if [[ -f "$UE_VALUES_FILE" ]]; then
        IMSI=$(grep -E "^\s*fullImsi:" "$UE_VALUES_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "")
        KEY=$(grep -E "^\s*fullKey:" "$UE_VALUES_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "$DEFAULT_KEY")
        OPC=$(grep -E "^\s*opc:" "$UE_VALUES_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "$DEFAULT_OPC")
        DNN=$(grep -E "^\s*dnn:" "$UE_VALUES_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "$DEFAULT_DNN")
        SST=$(grep -E "^\s*sst:" "$UE_VALUES_FILE" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "$DEFAULT_SST")
    fi
}

# Parse arguments
if [[ $# -eq 0 ]]; then
    extract_from_values
elif [[ $# -eq 1 ]]; then
    IMSI="$1"
    KEY="$DEFAULT_KEY"
    OPC="$DEFAULT_OPC"
    DNN="$DEFAULT_DNN"
    SST="$DEFAULT_SST"
else
    IMSI="${1:-}"
    KEY="${2:-$DEFAULT_KEY}"
    OPC="${3:-$DEFAULT_OPC}"
    DNN="${4:-$DEFAULT_DNN}"
    SST="${5:-$DEFAULT_SST}"
fi

# Validate IMSI
if [[ -z "$IMSI" ]]; then
    log_error "IMSI is required!"
    echo ""
    echo "Usage: $0 [IMSI] [KEY] [OPC] [DNN] [SST]"
    echo ""
    echo "Examples:"
    echo "  $0                              # Use values from bp-flexric/oai-nr-ue/values.yaml"
    echo "  $0 001010000000100              # Add specific IMSI with default keys"
    echo "  $0 001010000000101 <key> <opc>  # Add with custom credentials"
    exit 1
fi

# Find MySQL pod (pattern: oai-core-mysql-*)
log_info "Finding MySQL pod in namespace '$NAMESPACE'..."
MYSQL_POD=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -E 'oai-core-mysql|mysql' | grep -v Terminating | awk '{print $1}' | head -1)

if [[ -z "$MYSQL_POD" ]]; then
    log_error "MySQL pod not found in namespace '$NAMESPACE'"
    log_info "Available pods:"
    kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "  (none)"
    exit 1
fi

log_info "Found MySQL pod: $MYSQL_POD"

# Generate static IP from IMSI (last 3 digits as IP suffix)
IP_SUFFIX=$(echo "$IMSI" | tail -c 4 | sed 's/^0*//')
[[ -z "$IP_SUFFIX" || "$IP_SUFFIX" == "0" ]] && IP_SUFFIX="100"
STATIC_IP="12.1.1.$IP_SUFFIX"

log_info "Adding UE to database:"
echo "  IMSI:      $IMSI"
echo "  KEY:       ${KEY:0:8}..."
echo "  OPC:       ${OPC:0:8}..."
echo "  DNN:       $DNN"
echo "  SST:       $SST"
echo "  Static IP: $STATIC_IP"
echo ""

# Insert into database
kubectl exec -i "$MYSQL_POD" -n "$NAMESPACE" -- mysql -uroot -plinux -D oai_db 2>/dev/null <<EOF
-- Authentication Subscription
INSERT INTO AuthenticationSubscription (ueid, authenticationMethod, encPermanentKey, protectionParameterId, sequenceNumber, authenticationManagementField, algorithmId, encOpcKey, supi) VALUES 
('$IMSI', '5G_AKA', '$KEY', '$KEY', '{"sqn": "000000000020", "sqnScheme": "NON_TIME_BASED", "lastIndexes": {"ausf": 0}}', '8000', 'milenage', '$OPC', '$IMSI')
ON DUPLICATE KEY UPDATE 
    encPermanentKey='$KEY',
    encOpcKey='$OPC',
    authenticationMethod='5G_AKA';

-- Session Management Subscription
INSERT INTO SessionManagementSubscriptionData (ueid, servingPlmnid, singleNssai, dnnConfigurations) VALUES 
('$IMSI', '00101', '{"sst": $SST, "sd": "1"}', '{"$DNN":{"pduSessionTypes":{"defaultSessionType": "IPV4"},"sscModes": {"defaultSscMode": "SSC_MODE_1"},"5gQosProfile": {"5qi": 9,"arp":{"priorityLevel": 8,"preemptCap": "NOT_PREEMPT","preemptVuln":"NOT_PREEMPTABLE"},"priorityLevel":1},"sessionAmbr":{"uplink":"1000Mbps", "downlink":"1000Mbps"},"staticIpAddress":[{"ipv4Addr": "$STATIC_IP"}]}}')
ON DUPLICATE KEY UPDATE 
    dnnConfigurations='{"$DNN":{"pduSessionTypes":{"defaultSessionType": "IPV4"},"sscModes": {"defaultSscMode": "SSC_MODE_1"},"5gQosProfile": {"5qi": 9,"arp":{"priorityLevel": 8,"preemptCap": "NOT_PREEMPT","preemptVuln":"NOT_PREEMPTABLE"},"priorityLevel":1},"sessionAmbr":{"uplink":"1000Mbps", "downlink":"1000Mbps"},"staticIpAddress":[{"ipv4Addr": "$STATIC_IP"}]}}';

-- Access and Mobility Subscription
INSERT INTO AccessAndMobilitySubscriptionData (ueid, servingPlmnid, subscribedUeAmbr, nssai) VALUES
('$IMSI', '00101', '{"uplink":"1000Mbps","downlink":"1000Mbps"}', '{"defaultSingleNssais":[{"sst":$SST,"sd":"1"}],"singleNssais":[]}')
ON DUPLICATE KEY UPDATE 
    subscribedUeAmbr='{"uplink":"1000Mbps","downlink":"1000Mbps"}';

SELECT '------------------------------' as '';
SELECT CONCAT('✓ UE ', ueid, ' registered') as Status FROM AuthenticationSubscription WHERE ueid='$IMSI';
SELECT '------------------------------' as '';
EOF

if [[ $? -eq 0 ]]; then
    log_success "UE IMSI $IMSI added to database!"
    echo ""
    log_info "To verify, restart SMF and UE:"
    echo "  kubectl rollout restart deployment oai-smf -n $NAMESPACE"
    echo "  kubectl rollout restart deployment oai-nr-ue -n $NAMESPACE"
else
    log_error "Failed to add UE to database"
    exit 1
fi
