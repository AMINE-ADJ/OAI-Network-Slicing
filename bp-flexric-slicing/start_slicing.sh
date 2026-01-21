#!/bin/bash
# ============================================================
# 5G Network Slicing Deployment Script
# ============================================================
# This script deploys a 5G network with 2 slices:
# - Slice 1: eMBB (SST=1, SD=1) - UE1 (IMSI: 001010000000101)
# - Slice 2: uRLLC (SST=2, SD=1) - UE2 (IMSI: 001010000000102)
# ============================================================

set -e

# Configuration
NAMESPACE="blueprint"
BP_DIR="$(cd "$(dirname "$0")" && pwd)"
HELM_TIMEOUT="300s"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

wait_for_pod() {
    local pod_pattern=$1
    local max_wait=${2:-120}
    local counter=0
    
    log_info "Waiting for pod matching '$pod_pattern' to be ready..."
    while [ $counter -lt $max_wait ]; do
        if kubectl get pods -n $NAMESPACE 2>/dev/null | grep -q "$pod_pattern.*Running"; then
            log_success "Pod '$pod_pattern' is ready"
            return 0
        fi
        sleep 2
        counter=$((counter + 2))
    done
    log_error "Timeout waiting for pod '$pod_pattern'"
    return 1
}

wait_for_all_pods() {
    local max_wait=${1:-180}
    local counter=0
    
    log_info "Waiting for all pods in namespace '$NAMESPACE' to be ready..."
    while [ $counter -lt $max_wait ]; do
        local not_ready=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep -v "Running\|Completed\|NAME" | wc -l)
        if [ "$not_ready" -eq 0 ]; then
            local running=$(kubectl get pods -n $NAMESPACE 2>/dev/null | grep "Running" | wc -l)
            if [ "$running" -gt 0 ]; then
                log_success "All $running pods are ready"
                return 0
            fi
        fi
        sleep 5
        counter=$((counter + 5))
        echo -ne "\r  Waiting... ($counter/$max_wait seconds)"
    done
    echo ""
    log_warning "Some pods may not be ready after $max_wait seconds"
    kubectl get pods -n $NAMESPACE
    return 1
}

add_ue_subscribers() {
    log_info "Adding UE subscribers to the database..."
    
    # Wait for MySQL pod
    local mysql_pod=""
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        mysql_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep -E 'mysql' | head -1 | cut -d'/' -f2)
        if [ -n "$mysql_pod" ]; then
            # Check if MySQL is ready
            if kubectl exec -n $NAMESPACE "$mysql_pod" -- mysql -u test -ptest -e "SELECT 1" 2>/dev/null; then
                break
            fi
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ -z "$mysql_pod" ]; then
        log_error "Could not find MySQL pod"
        return 1
    fi
    
    log_info "MySQL pod: $mysql_pod"
    
    # Add UE1 for Slice 1 (IMSI: 001010000000101)
    log_info "Adding UE1 (Slice 1) - IMSI: 001010000000101"
    kubectl exec -n $NAMESPACE "$mysql_pod" -- mysql -u test -ptest oai_db -e "
    INSERT IGNORE INTO AuthenticationSubscription (ueid, authenticationMethod, encPermanentKey, protectionParameterId, sequenceNumber, authenticationManagementField, algorithmId, encOpcKey, encTopcKey, vectorGenerationInHss, n5telecomMacKey, simMac, simOpc, simOp, usimMac, usimOpc, usimOp)
    VALUES ('001010000000101', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', 'C42449363BBAD02B66D16BC975D77CC1', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    " 2>/dev/null || log_warning "UE1 may already exist"
    
    kubectl exec -n $NAMESPACE "$mysql_pod" -- mysql -u test -ptest oai_db -e "
    INSERT IGNORE INTO SessionManagementSubscriptionData (ueid, servingPlmnid, singleNssai, dnnConfigurations)
    VALUES ('001010000000101', '00101', '{\"sst\": 1, \"sd\": \"000001\"}', '{\"slice1\":{\"pduSessionTypes\":{ \"defaultSessionType\": \"IPV4\"},\"sscModes\": {\"defaultSscMode\": \"SSC_MODE_1\"},\"5gQosProfile\": {\"5qi\": 9,\"arp\":{\"priorityLevel\": 8,\"preemptCap\": \"NOT_PREEMPT\",\"preemptVuln\":\"NOT_PREEMPTABLE\"},\"priorityLevel\":1},\"sessionAmbr\":{\"uplink\":\"1000Mbps\", \"downlink\":\"1000Mbps\"},\"staticIpAddress\":[]}}');
    " 2>/dev/null || log_warning "UE1 session data may already exist"
    
    kubectl exec -n $NAMESPACE "$mysql_pod" -- mysql -u test -ptest oai_db -e "
    INSERT IGNORE INTO AccessAndMobilitySubscriptionData (ueid, servingPlmnid, supportedFeatures, gpsis, internalGroupIds, sharedVnGroupDataIds, subscribedUeAmbr, nssai, ratRestrictions, forbiddenAreas, serviceAreaRestriction, coreNetworkTypeRestrictions, rfspIndex, subsRegTimer, ueUsageType, mpsPriority, mcsPriority, activeTime, sorInfo, sorInfoExpectInd, sorafRetrieval, sorUpdateIndicatorList, upuInfo, micoAllowed, sharedAmDataIds, odtEntryList, subscriptionDataSets, dlPacketCount, traceData, additionalTraceData)
    VALUES ('001010000000101', '00101', NULL, NULL, NULL, NULL, '{\"uplink\":\"1Gbps\",\"downlink\":\"2Gbps\"}', '{\"defaultSingleNssais\":[{\"sst\":1,\"sd\":\"000001\"}]}', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    " 2>/dev/null || log_warning "UE1 access data may already exist"
    
    # Add UE2 for Slice 2 (IMSI: 001010000000102)
    log_info "Adding UE2 (Slice 2) - IMSI: 001010000000102"
    kubectl exec -n $NAMESPACE "$mysql_pod" -- mysql -u test -ptest oai_db -e "
    INSERT IGNORE INTO AuthenticationSubscription (ueid, authenticationMethod, encPermanentKey, protectionParameterId, sequenceNumber, authenticationManagementField, algorithmId, encOpcKey, encTopcKey, vectorGenerationInHss, n5telecomMacKey, simMac, simOpc, simOp, usimMac, usimOpc, usimOp)
    VALUES ('001010000000102', '5G_AKA', 'fec86ba6eb707ed08905757b1bb44b8f', 'fec86ba6eb707ed08905757b1bb44b8f', '{\"sqn\": \"000000000020\", \"sqnScheme\": \"NON_TIME_BASED\", \"lastIndexes\": {\"ausf\": 0}}', '8000', 'milenage', 'C42449363BBAD02B66D16BC975D77CC1', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    " 2>/dev/null || log_warning "UE2 may already exist"
    
    kubectl exec -n $NAMESPACE "$mysql_pod" -- mysql -u test -ptest oai_db -e "
    INSERT IGNORE INTO SessionManagementSubscriptionData (ueid, servingPlmnid, singleNssai, dnnConfigurations)
    VALUES ('001010000000102', '00101', '{\"sst\": 2, \"sd\": \"000001\"}', '{\"slice2\":{\"pduSessionTypes\":{ \"defaultSessionType\": \"IPV4\"},\"sscModes\": {\"defaultSscMode\": \"SSC_MODE_1\"},\"5gQosProfile\": {\"5qi\": 1,\"arp\":{\"priorityLevel\": 8,\"preemptCap\": \"NOT_PREEMPT\",\"preemptVuln\":\"NOT_PREEMPTABLE\"},\"priorityLevel\":1},\"sessionAmbr\":{\"uplink\":\"500Mbps\", \"downlink\":\"500Mbps\"},\"staticIpAddress\":[]}}');
    " 2>/dev/null || log_warning "UE2 session data may already exist"
    
    kubectl exec -n $NAMESPACE "$mysql_pod" -- mysql -u test -ptest oai_db -e "
    INSERT IGNORE INTO AccessAndMobilitySubscriptionData (ueid, servingPlmnid, supportedFeatures, gpsis, internalGroupIds, sharedVnGroupDataIds, subscribedUeAmbr, nssai, ratRestrictions, forbiddenAreas, serviceAreaRestriction, coreNetworkTypeRestrictions, rfspIndex, subsRegTimer, ueUsageType, mpsPriority, mcsPriority, activeTime, sorInfo, sorInfoExpectInd, sorafRetrieval, sorUpdateIndicatorList, upuInfo, micoAllowed, sharedAmDataIds, odtEntryList, subscriptionDataSets, dlPacketCount, traceData, additionalTraceData)
    VALUES ('001010000000102', '00101', NULL, NULL, NULL, NULL, '{\"uplink\":\"500Mbps\",\"downlink\":\"1Gbps\"}', '{\"defaultSingleNssais\":[{\"sst\":2,\"sd\":\"000001\"}]}', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    " 2>/dev/null || log_warning "UE2 access data may already exist"
    
    log_success "UE subscribers added successfully"
}

deploy_core() {
    log_info "============================================"
    log_info "Deploying 5G Core Network Functions"
    log_info "============================================"
    
    # Deploy MySQL
    log_info "Deploying MySQL..."
    helm upgrade --install oai-core-mysql "$BP_DIR/oai-5g-core/mysql" \
        -n $NAMESPACE --create-namespace \
        --wait --timeout $HELM_TIMEOUT
    
    wait_for_pod "mysql" 120
    sleep 5  # Extra time for MySQL to initialize
    
    # Deploy NRF
    log_info "Deploying NRF..."
    helm upgrade --install oai-core-nrf "$BP_DIR/oai-5g-core/oai-nrf" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    # Deploy UDR
    log_info "Deploying UDR..."
    helm upgrade --install oai-core-udr "$BP_DIR/oai-5g-core/oai-udr" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    # Deploy UDM
    log_info "Deploying UDM..."
    helm upgrade --install oai-core-udm "$BP_DIR/oai-5g-core/oai-udm" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    # Deploy AUSF
    log_info "Deploying AUSF..."
    helm upgrade --install oai-core-ausf "$BP_DIR/oai-5g-core/oai-ausf" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    # Deploy AMF (shared for both slices)
    log_info "Deploying AMF (shared)..."
    helm upgrade --install oai-core-amf "$BP_DIR/oai-5g-core/oai-amf" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    # Deploy SMF and UPF for Slice 1
    log_info "Deploying SMF-Slice1..."
    helm upgrade --install oai-smf-slice1 "$BP_DIR/oai-5g-core/oai-smf-slice1" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    log_info "Deploying UPF-Slice1..."
    helm upgrade --install oai-upf-slice1 "$BP_DIR/oai-5g-core/oai-upf-slice1" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    # Deploy SMF and UPF for Slice 2
    log_info "Deploying SMF-Slice2..."
    helm upgrade --install oai-smf-slice2 "$BP_DIR/oai-5g-core/oai-smf-slice2" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    log_info "Deploying UPF-Slice2..."
    helm upgrade --install oai-upf-slice2 "$BP_DIR/oai-5g-core/oai-upf-slice2" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    log_success "5G Core Network deployed with 2 slices"
}

deploy_flexric() {
    log_info "============================================"
    log_info "Deploying FlexRIC"
    log_info "============================================"
    
    # Build FlexRIC if needed
    if ! kubectl get pods -n $NAMESPACE 2>/dev/null | grep -q "flexric.*Running"; then
        log_info "Deploying FlexRIC build job..."
        helm upgrade --install oai-flexric-build "$BP_DIR/flexric-build" \
            -n $NAMESPACE --wait --timeout 600s 2>/dev/null || true
    fi
    
    log_info "Deploying FlexRIC..."
    helm upgrade --install oai-flexric "$BP_DIR/oai-flexric" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    wait_for_pod "flexric" 120
    log_success "FlexRIC deployed"
}

deploy_ran() {
    log_info "============================================"
    log_info "Deploying RAN (gNB)"
    log_info "============================================"
    
    log_info "Deploying gNB with multi-slice support..."
    helm upgrade --install oai-ran "$BP_DIR/oai-gnb" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    wait_for_pod "oai-ran\|oai-gnb" 120
    log_success "gNB deployed with Slice 1 (SST=1) and Slice 2 (SST=2) support"
}

deploy_ues() {
    log_info "============================================"
    log_info "Deploying UEs"
    log_info "============================================"
    
    # Deploy UE for Slice 1
    log_info "Deploying UE1 (Slice 1 - eMBB)..."
    helm upgrade --install oai-nr-ue-slice1 "$BP_DIR/oai-nr-ue-slice1" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    # Deploy UE for Slice 2
    log_info "Deploying UE2 (Slice 2 - uRLLC)..."
    helm upgrade --install oai-nr-ue-slice2 "$BP_DIR/oai-nr-ue-slice2" \
        -n $NAMESPACE --wait --timeout $HELM_TIMEOUT
    
    log_success "UEs deployed for both slices"
}

verify_connectivity() {
    log_info "============================================"
    log_info "Verifying Network Connectivity"
    log_info "============================================"
    
    local max_attempts=30
    local attempt=0
    local ue1_ip=""
    local ue2_ip=""
    
    # Wait for UE1 to get IP
    log_info "Waiting for UE1 to establish PDU session..."
    while [ $attempt -lt $max_attempts ]; do
        ue1_ip=$(kubectl logs -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2) 2>/dev/null | grep -oP "Interface oaitun_ue1 successfully configured, ip address \K[0-9.]+" | tail -1)
        if [ -n "$ue1_ip" ]; then
            log_success "UE1 got IP: $ue1_ip"
            break
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ -z "$ue1_ip" ]; then
        log_warning "UE1 did not get IP address within timeout"
    fi
    
    # Wait for UE2 to get IP
    attempt=0
    log_info "Waiting for UE2 to establish PDU session..."
    while [ $attempt -lt $max_attempts ]; do
        ue2_ip=$(kubectl logs -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2) 2>/dev/null | grep -oP "Interface oaitun_ue1 successfully configured, ip address \K[0-9.]+" | tail -1)
        if [ -n "$ue2_ip" ]; then
            log_success "UE2 got IP: $ue2_ip"
            break
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    if [ -z "$ue2_ip" ]; then
        log_warning "UE2 did not get IP address within timeout"
    fi
    
    # Test ping from UE1
    if [ -n "$ue1_ip" ]; then
        log_info "Testing ping from UE1 to UPF gateway (12.1.1.1)..."
        local ue1_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2)
        if kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- ping -c 3 -I oaitun_ue1 12.1.1.1 >/dev/null 2>&1; then
            log_success "UE1 ping to UPF gateway successful!"
        else
            log_warning "UE1 ping to UPF gateway failed"
        fi
    fi
    
    # Test ping from UE2
    if [ -n "$ue2_ip" ]; then
        log_info "Testing ping from UE2 to UPF gateway (12.2.1.1)..."
        local ue2_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2)
        if kubectl exec -n $NAMESPACE "$ue2_pod" -c nr-ue -- ping -c 3 -I oaitun_ue1 12.2.1.1 >/dev/null 2>&1; then
            log_success "UE2 ping to UPF gateway successful!"
        else
            log_warning "UE2 ping to UPF gateway failed"
        fi
    fi
    
    # Test internet connectivity from UE1
    if [ -n "$ue1_ip" ]; then
        log_info "Testing internet connectivity from UE1..."
        local ue1_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2)
        if kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- ping -c 3 -I oaitun_ue1 8.8.8.8 >/dev/null 2>&1; then
            log_success "UE1 internet connectivity working!"
        else
            log_warning "UE1 internet connectivity failed (may need NAT configuration)"
        fi
    fi
    
    echo ""
    log_info "============================================"
    log_info "Connectivity Summary"
    log_info "============================================"
    echo -e "
${GREEN}UE1 (Slice 1 - eMBB):${NC}
  - IP Address: ${ue1_ip:-NOT ASSIGNED}
  - Expected Range: 12.1.1.0/24

${YELLOW}UE2 (Slice 2 - uRLLC):${NC}
  - IP Address: ${ue2_ip:-NOT ASSIGNED}
  - Expected Range: 12.2.1.0/24
"
}

test_slicing() {
    log_info "============================================"
    log_info "Network Slicing Verification Tests"
    log_info "============================================"
    
    local ue1_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2)
    local ue2_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2)
    
    if [ -z "$ue1_pod" ] || [ -z "$ue2_pod" ]; then
        log_error "UE pods not found. Deploy first with: $0 deploy"
        return 1
    fi
    
    echo ""
    log_info "1. Verifying Slice Assignment (S-NSSAI)"
    log_info "----------------------------------------"
    
    echo -n "   UE1: "
    local ue1_slice=$(kubectl logs -n $NAMESPACE "$ue1_pod" 2>/dev/null | grep -oP "SST=0x\K[0-9a-f]+.*SD=0x[0-9a-f]+" | tail -1)
    if [ -n "$ue1_slice" ]; then
        echo -e "${GREEN}SST=$ue1_slice${NC}"
    else
        echo -e "${RED}Not found${NC}"
    fi
    
    echo -n "   UE2: "
    local ue2_slice=$(kubectl logs -n $NAMESPACE "$ue2_pod" 2>/dev/null | grep -oP "SST=0x\K[0-9a-f]+.*SD=0x[0-9a-f]+" | tail -1)
    if [ -n "$ue2_slice" ]; then
        echo -e "${GREEN}SST=$ue2_slice${NC}"
    else
        echo -e "${RED}Not found${NC}"
    fi
    
    echo ""
    log_info "2. Verifying IP Address Pools (Traffic Isolation)"
    log_info "-------------------------------------------------"
    
    local ue1_ip=$(kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- ip addr show oaitun_ue1 2>/dev/null | grep -oP "inet \K[0-9.]+")
    local ue2_ip=$(kubectl exec -n $NAMESPACE "$ue2_pod" -c nr-ue -- ip addr show oaitun_ue1 2>/dev/null | grep -oP "inet \K[0-9.]+")
    
    echo -e "   UE1 IP: ${GREEN}${ue1_ip:-NOT ASSIGNED}${NC} (expected: 12.1.1.x)"
    echo -e "   UE2 IP: ${YELLOW}${ue2_ip:-NOT ASSIGNED}${NC} (expected: 12.2.1.x)"
    
    # Verify IPs are in correct ranges
    if [[ "$ue1_ip" == 12.1.1.* ]] && [[ "$ue2_ip" == 12.2.1.* ]]; then
        log_success "IP pools correctly isolated per slice!"
    else
        log_warning "IP addresses may not be in expected ranges"
    fi
    
    echo ""
    log_info "3. Verifying QoS Profiles"
    log_info "-------------------------"
    
    echo "   Slice 1 (eMBB):"
    kubectl logs -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -o name | grep oai-smf-slice1 | head -1 | cut -d'/' -f2) 2>/dev/null | grep -E "5qi|session_ambr" | head -3 | sed 's/^/      /'
    
    echo "   Slice 2 (uRLLC):"
    kubectl logs -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -o name | grep oai-smf-slice2 | head -1 | cut -d'/' -f2) 2>/dev/null | grep -E "5qi|session_ambr" | head -3 | sed 's/^/      /'
    
    echo ""
    log_info "4. Latency Comparison (ping 8.8.8.8)"
    log_info "------------------------------------"
    
    echo "   UE1 (Slice 1 - eMBB, 5QI=9):"
    kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- ping -c 5 -i 0.2 -I oaitun_ue1 8.8.8.8 2>&1 | grep -E "^(PING|rtt|---)" | sed 's/^/      /'
    
    echo "   UE2 (Slice 2 - uRLLC, 5QI=1):"
    kubectl exec -n $NAMESPACE "$ue2_pod" -c nr-ue -- ping -c 5 -i 0.2 -I oaitun_ue1 8.8.8.8 2>&1 | grep -E "^(PING|rtt|---)" | sed 's/^/      /'
    
    echo ""
    log_info "5. AMF Slice Selection Verification"
    log_info "------------------------------------"
    
    local smf1_selected=$(kubectl logs -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -o name | grep oai-amf | head -1 | cut -d'/' -f2) 2>/dev/null | grep -c "SMF profile.*sst.*1")
    local smf2_selected=$(kubectl logs -n $NAMESPACE $(kubectl get pods -n $NAMESPACE -o name | grep oai-amf | head -1 | cut -d'/' -f2) 2>/dev/null | grep -c "SMF profile.*sst.*2")
    
    echo -e "   SMF-slice1 selections (SST=1): ${GREEN}${smf1_selected}${NC}"
    echo -e "   SMF-slice2 selections (SST=2): ${YELLOW}${smf2_selected}${NC}"
    
    echo ""
    echo "========================================"
    echo "         SLICING STATUS SUMMARY         "
    echo "========================================"
    echo ""
    
    local all_pass=true
    
    # Check slice assignment
    if [[ "$ue1_slice" == *"01"* ]] && [[ "$ue2_slice" == *"02"* ]]; then
        echo -e "  [${GREEN}✓${NC}] Slice Assignment: UE1→Slice1, UE2→Slice2"
    else
        echo -e "  [${RED}✗${NC}] Slice Assignment: Check failed"
        all_pass=false
    fi
    
    # Check IP isolation
    if [[ "$ue1_ip" == 12.1.1.* ]] && [[ "$ue2_ip" == 12.2.1.* ]]; then
        echo -e "  [${GREEN}✓${NC}] Traffic Isolation: IPs in separate pools"
    else
        echo -e "  [${RED}✗${NC}] Traffic Isolation: Check failed"
        all_pass=false
    fi
    
    # Check connectivity
    if kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- ping -c 1 -I oaitun_ue1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "  [${GREEN}✓${NC}] UE1 Connectivity: Working"
    else
        echo -e "  [${RED}✗${NC}] UE1 Connectivity: Failed"
        all_pass=false
    fi
    
    if kubectl exec -n $NAMESPACE "$ue2_pod" -c nr-ue -- ping -c 1 -I oaitun_ue1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "  [${GREEN}✓${NC}] UE2 Connectivity: Working"
    else
        echo -e "  [${RED}✗${NC}] UE2 Connectivity: Failed"
        all_pass=false
    fi
    
    echo ""
    if [ "$all_pass" = true ]; then
        log_success "All slicing tests PASSED!"
    else
        log_warning "Some tests failed - check above for details"
    fi
    
    echo ""
    echo -e "${BLUE}Note:${NC} RTT may be similar because RF Simulator doesn't"
    echo "      simulate real radio latency. 5QI differentiation"
    echo "      is effective under congestion scenarios."
}

run_benchmark() {
    log_info "╔══════════════════════════════════════════════════════════════╗"
    log_info "║      5G NETWORK SLICING - PERFORMANCE BENCHMARK             ║"
    log_info "╚══════════════════════════════════════════════════════════════╝"
    
    local ue1_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2)
    local ue2_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2)
    local upf1_pod=$(kubectl get pods -n $NAMESPACE -o name 2>/dev/null | grep oai-upf-slice1 | head -1 | cut -d'/' -f2)
    
    if [ -z "$ue1_pod" ] || [ -z "$ue2_pod" ]; then
        log_error "UE pods not found. Deploy first with: $0 deploy"
        return 1
    fi
    
    # Ensure iperf3 server is running on UPF
    log_info "Setting up iperf3 server on UPF-slice1..."
    kubectl exec -n $NAMESPACE "$upf1_pod" -- pkill iperf3 2>/dev/null || true
    kubectl exec -n $NAMESPACE "$upf1_pod" -- iperf3 -s -D 2>/dev/null
    sleep 2
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "                    1. LATENCY TEST (RTT)                       "
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    log_info "Testing latency with 20 ICMP packets to 8.8.8.8..."
    echo ""
    
    echo -e "${GREEN}UE1 (Slice 1 - eMBB, 5QI=9):${NC}"
    local ue1_latency=$(kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- ping -c 20 -i 0.1 -I oaitun_ue1 8.8.8.8 2>&1)
    echo "$ue1_latency" | grep -E "^(PING|rtt|---)"
    local ue1_avg=$(echo "$ue1_latency" | grep "rtt" | awk -F'/' '{print $5}')
    
    echo ""
    echo -e "${YELLOW}UE2 (Slice 2 - uRLLC, 5QI=1):${NC}"
    local ue2_latency=$(kubectl exec -n $NAMESPACE "$ue2_pod" -c nr-ue -- ping -c 20 -i 0.1 -I oaitun_ue1 8.8.8.8 2>&1)
    echo "$ue2_latency" | grep -E "^(PING|rtt|---)"
    local ue2_avg=$(echo "$ue2_latency" | grep "rtt" | awk -F'/' '{print $5}')
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "                 2. THROUGHPUT TEST (iperf3)                    "
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    log_info "Testing throughput UE → UPF (5 second tests)..."
    echo ""
    
    echo -e "${GREEN}UE1 (Slice 1) UPLOAD to UPF-slice1:${NC}"
    local ue1_ul=$(kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- timeout 10 iperf3 -c 12.1.1.1 -t 5 -B 12.1.1.2 2>&1)
    echo "$ue1_ul" | grep -E "sender|receiver" | tail -2
    local ue1_ul_bw=$(echo "$ue1_ul" | grep "sender" | awk '{print $7" "$8}')
    
    echo ""
    echo -e "${GREEN}UE1 (Slice 1) DOWNLOAD from UPF-slice1:${NC}"
    local ue1_dl=$(kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- timeout 10 iperf3 -c 12.1.1.1 -t 5 -R -B 12.1.1.2 2>&1)
    echo "$ue1_dl" | grep -E "sender|receiver" | tail -2
    local ue1_dl_bw=$(echo "$ue1_dl" | grep "receiver" | awk '{print $7" "$8}')
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "                   3. FAIRNESS TEST                             "
    echo "    (Testing slice isolation under heavy load)                  "
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    log_info "Step 1: Baseline latency for UE2 (Slice 2) - no load..."
    local baseline=$(kubectl exec -n $NAMESPACE "$ue2_pod" -c nr-ue -- ping -c 10 -i 0.2 -I oaitun_ue1 8.8.8.8 2>&1)
    local baseline_avg=$(echo "$baseline" | grep "rtt" | awk -F'/' '{print $5}')
    echo "  Baseline RTT: ${baseline_avg} ms"
    
    echo ""
    log_info "Step 2: Starting heavy load on UE1 (Slice 1)..."
    kubectl exec -n $NAMESPACE "$ue1_pod" -c nr-ue -- timeout 20 iperf3 -c 12.1.1.1 -t 15 -P 4 -B 12.1.1.2 >/dev/null 2>&1 &
    local load_pid=$!
    sleep 3
    
    log_info "Step 3: Measuring UE2 latency WHILE UE1 is under heavy load..."
    local loaded=$(kubectl exec -n $NAMESPACE "$ue2_pod" -c nr-ue -- ping -c 10 -i 0.2 -I oaitun_ue1 8.8.8.8 2>&1)
    local loaded_avg=$(echo "$loaded" | grep "rtt" | awk -F'/' '{print $5}')
    echo "  Loaded RTT: ${loaded_avg} ms"
    
    # Wait for load test to finish
    wait $load_pid 2>/dev/null
    
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "                  BENCHMARK RESULTS SUMMARY                     "
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                    LATENCY (RTT to 8.8.8.8)                 │"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│  UE1 (Slice 1 - eMBB, 5QI=9):    %-20s       │\n" "${ue1_avg:-N/A} ms"
    printf "│  UE2 (Slice 2 - uRLLC, 5QI=1):   %-20s       │\n" "${ue2_avg:-N/A} ms"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│                    THROUGHPUT (to UPF)                      │"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│  UE1 Upload:                     %-20s       │\n" "${ue1_ul_bw:-N/A}"
    printf "│  UE1 Download:                   %-20s       │\n" "${ue1_dl_bw:-N/A}"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│                    FAIRNESS (Slice Isolation)               │"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│  UE2 Baseline RTT:               %-20s       │\n" "${baseline_avg:-N/A} ms"
    printf "│  UE2 RTT under UE1 load:         %-20s       │\n" "${loaded_avg:-N/A} ms"
    echo "└─────────────────────────────────────────────────────────────┘"
    
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                    CONFIGURED QoS PROFILES                  │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│  Slice 1 (eMBB):   5QI=9   AMBR: DL=1000Mbps UL=500Mbps    │"
    echo "│  Slice 2 (uRLLC):  5QI=1   AMBR: DL=400Mbps  UL=200Mbps    │"
    echo "└─────────────────────────────────────────────────────────────┘"
    
    echo ""
    echo -e "${BLUE}Analysis:${NC}"
    echo "• Throughput is limited by RF Simulator (not real radio)"
    echo "• Internet latency (~40ms) dominates over radio latency"
    echo "• Fairness test shows if Slice 2 latency increases under Slice 1 load"
    echo "• For production QoS testing, use real gNB hardware"
}

show_status() {
    echo ""
    log_info "============================================"
    log_info "Deployment Status"
    log_info "============================================"
    echo ""
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
    log_info "============================================"
    log_info "Services"
    log_info "============================================"
    echo ""
    kubectl get svc -n $NAMESPACE
    echo ""
    log_info "============================================"
    log_info "Slicing Configuration Summary"
    log_info "============================================"
    echo -e "
${GREEN}Slice 1 (eMBB):${NC}
  - SST: 1, SD: 1
  - DNN: slice1
  - IP Pool: 12.1.1.0/24
  - SMF: oai-smf-slice1
  - UPF: oai-upf-slice1
  - UE: oai-nr-ue-slice1 (IMSI: 001010000000101)

${YELLOW}Slice 2 (uRLLC):${NC}
  - SST: 2, SD: 1
  - DNN: slice2
  - IP Pool: 12.2.1.0/24
  - SMF: oai-smf-slice2
  - UPF: oai-upf-slice2
  - UE: oai-nr-ue-slice2 (IMSI: 001010000000102)

${BLUE}Shared Components:${NC}
  - AMF: oai-amf (handles both slices)
  - gNB: oai-ran (supports both S-NSSAIs)
  - FlexRIC: oai-flexric
"
}

cleanup() {
    log_info "Cleaning up existing deployment..."
    
    # Delete UEs
    helm uninstall oai-nr-ue-slice1 -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-nr-ue-slice2 -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-nr-ue -n $NAMESPACE 2>/dev/null || true
    
    # Delete RAN
    helm uninstall oai-ran -n $NAMESPACE 2>/dev/null || true
    
    # Delete FlexRIC
    helm uninstall oai-flexric -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-flexric-build -n $NAMESPACE 2>/dev/null || true
    
    # Delete Core (sliced components)
    helm uninstall oai-upf-slice1 -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-upf-slice2 -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-smf-slice1 -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-smf-slice2 -n $NAMESPACE 2>/dev/null || true
    
    # Delete Core (shared components)
    helm uninstall oai-core-amf -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-core-ausf -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-core-udm -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-core-udr -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-core-nrf -n $NAMESPACE 2>/dev/null || true
    helm uninstall oai-core-mysql -n $NAMESPACE 2>/dev/null || true
    
    # Wait for pods to terminate
    log_info "Waiting for pods to terminate..."
    sleep 10
    
    log_success "Cleanup complete"
}

# Main script
main() {
    case "${1:-deploy}" in
        deploy|start)
            echo ""
            log_info "============================================"
            log_info "5G Network Slicing Deployment"
            log_info "============================================"
            echo ""
            
            deploy_core
            sleep 10
            
            # Add UE subscribers to database
            add_ue_subscribers
            sleep 5
            
            # Deploy FlexRIC (needed for gNB E2 agent)
            deploy_flexric
            sleep 10
            
            deploy_ran
            sleep 15
            
            deploy_ues
            sleep 10
            
            wait_for_all_pods 300
            
            # Verify connectivity
            verify_connectivity
            
            show_status
            
            log_success "5G Network with 2 slices deployed successfully!"
            ;;
        
        cleanup|destroy|stop)
            cleanup
            ;;
        
        status)
            show_status
            ;;
        
        core)
            deploy_core
            add_ue_subscribers
            ;;
        
        ran)
            deploy_ran
            ;;
        
        ue|ues)
            deploy_ues
            ;;
        
        flexric)
            deploy_flexric
            ;;
        
        subscribers)
            add_ue_subscribers
            ;;
        
        verify)
            verify_connectivity
            ;;
        
        test)
            test_slicing
            ;;
        
        benchmark|perf)
            run_benchmark
            ;;
        
        *)
            echo "Usage: $0 {deploy|cleanup|status|core|ran|ue|flexric|subscribers|verify|test|benchmark}"
            echo ""
            echo "Commands:"
            echo "  deploy      - Deploy full 5G network with slicing"
            echo "  cleanup     - Remove all deployed components"
            echo "  status      - Show current deployment status"
            echo "  core        - Deploy only core network"
            echo "  ran         - Deploy only gNB"
            echo "  ue          - Deploy only UEs"
            echo "  flexric     - Deploy only FlexRIC"
            echo "  subscribers - Add UE subscribers to database"
            echo "  verify      - Verify UE connectivity"
            echo "  test        - Run slicing verification tests"
            echo "  benchmark   - Run full performance benchmark (throughput, latency, fairness)"
            exit 1
            ;;
    esac
}

main "$@"
