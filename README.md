# 5G Network Slicing Project - Complete Guide

## Project Overview

This project deploys a complete **5G network with Network Slicing** using OpenAirInterface (OAI) on Kubernetes (Minikube). It demonstrates QoS differentiation between two slices:

| Slice | Type | SST | SD | DNN | 5QI | IP Pool | Purpose |
|-------|------|-----|-----|-----|-----|---------|---------|
| **Slice 1** | eMBB | 1 | 1 | slice1 | 9 | 12.1.1.0/24 | High bandwidth (video, data) |
| **Slice 2** | uRLLC | 2 | 1 | slice2 | 1 | 12.2.1.0/24 | Low latency (robotics, gaming) |

---

## 1. Deployment

### Deploy the Full Network
```bash
cd /mnt/Studies/Sorbonne/Nova/Network-Slicing-using-OAI-and-OAI-5GC
./bp-flexric-slicing/start_slicing.sh deploy
```

This deploys 14 pods: MySQL, NRF, UDR, UDM, AUSF, AMF, SMF-Slice1, SMF-Slice2, UPF-Slice1, UPF-Slice2, FlexRIC, gNB, UE1, UE2.

### Cleanup
```bash
./bp-flexric-slicing/start_slicing.sh cleanup
```

---

## 2. Verify All Pods Running

```bash
kubectl get pods -n blueprint
```

**Expected output:** All 14 pods should be `Running` (1/1 Ready).

---

## 3. Verify AMF Registration (gNB & UEs)

### Check gNB Registration
```bash
kubectl logs -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-amf | head -1 | cut -d'/' -f2) | grep -i "gNB"
```

### Check UE Registrations
```bash
kubectl logs -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-amf | head -1 | cut -d'/' -f2) | grep -E "REGISTERED|Registration"
```

### Verify Both UEs Connected
```bash
kubectl logs -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-amf | head -1 | cut -d'/' -f2) | grep -E "001010000000101|001010000000102"
```

---

## 4. Basic Connectivity Test (UE → UPF)

### Get UE IP Addresses
```bash
# UE1 - Slice 1
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2) -c nr-ue -- ip addr show oaitun_ue1 | grep inet

# UE2 - Slice 2  
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2) -c nr-ue -- ip addr show oaitun_ue1 | grep inet
```

**Expected:** UE1 should have IP in `12.1.1.x` range, UE2 in `12.2.1.x` range.

### Ping UPF Gateway from UE1
```bash
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2) -c nr-ue -- ping -c 3 -I oaitun_ue1 12.1.1.1
```

### Ping UPF Gateway from UE2
```bash
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2) -c nr-ue -- ping -c 3 -I oaitun_ue1 12.2.1.1
```

### Ping Internet (8.8.8.8)
```bash
# From UE1
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2) -c nr-ue -- ping -c 3 -I oaitun_ue1 8.8.8.8

# From UE2
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2) -c nr-ue -- ping -c 3 -I oaitun_ue1 8.8.8.8
```

---

## 5. Slice Configuration Locations (S-NSSAI)

### AMF Configuration (Routes UEs to correct SMF)
```bash
cat bp-flexric-slicing/oai-5g-core/oai-amf/config.yaml | grep -A 20 "plmn_support_list"
```
Key: `nssai` section defines supported slices (SST=1,SD=1 and SST=2,SD=1)

### SMF-Slice1 Configuration (eMBB)
```bash
cat bp-flexric-slicing/oai-5g-core/oai-smf-slice1/config.yaml | grep -A 10 "snssais"
```

### SMF-Slice2 Configuration (uRLLC)
```bash
cat bp-flexric-slicing/oai-5g-core/oai-smf-slice2/config.yaml | grep -A 10 "snssais"
```

### UPF-Slice1 Configuration
```bash
cat bp-flexric-slicing/oai-5g-core/oai-upf-slice1/config.yaml | grep -A 10 "snssais"
```

### UPF-Slice2 Configuration
```bash
cat bp-flexric-slicing/oai-5g-core/oai-upf-slice2/config.yaml | grep -A 10 "snssais"
```

### gNB Configuration (Advertises both slices)
```bash
cat bp-flexric-slicing/oai-gnb/config.yaml | grep -A 10 "plmn_list"
```

---

## 6. UE Configuration (Slice Selection)

### UE1 - Requests Slice 1 (eMBB)
```bash
cat bp-flexric-slicing/oai-nr-ue-slice1/values.yaml | grep -A 10 "nssai"
```
Key settings: `IMSI=001010000000101`, `DNN=slice1`, `SST=1`, `SD=1`

### UE2 - Requests Slice 2 (uRLLC)
```bash
cat bp-flexric-slicing/oai-nr-ue-slice2/values.yaml | grep -A 10 "nssai"
```
Key settings: `IMSI=001010000000102`, `DNN=slice2`, `SST=2`, `SD=1`

### Database Subscriptions (UDR)
```bash
# Check UE1 subscription
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep mysql | head -1 | cut -d'/' -f2) -- mysql -u test -ptest oai_db -e "SELECT ueid, singleNssai FROM SessionManagementSubscriptionData WHERE ueid='001010000000101';"

# Check UE2 subscription
kubectl exec -n blueprint $(kubectl get pods -n blueprint -o name | grep mysql | head -1 | cut -d'/' -f2) -- mysql -u test -ptest oai_db -e "SELECT ueid, singleNssai FROM SessionManagementSubscriptionData WHERE ueid='001010000000102';"
```

---

## 7. Performance Testing Commands

### Set Pod Variables First
```bash
export NAMESPACE="blueprint"
export UE1_POD=$(kubectl get pods -n $NAMESPACE -o name | grep oai-nr-ue-slice1 | head -1 | cut -d'/' -f2)
export UE2_POD=$(kubectl get pods -n $NAMESPACE -o name | grep oai-nr-ue-slice2 | head -1 | cut -d'/' -f2)
export UPF1_POD=$(kubectl get pods -n $NAMESPACE -o name | grep oai-upf-slice1 | head -1 | cut -d'/' -f2)
```

---

### TEST A: Fairness Test (Slice Isolation)

**Goal:** Verify that heavy load on Slice 1 doesn't impact Slice 2 latency.

#### Step 1: Baseline latency for UE2 (no load)
```bash
kubectl exec -n $NAMESPACE "$UE2_POD" -c nr-ue -- ping -c 10 -i 0.2 -I oaitun_ue1 8.8.8.8
```
*Note the average RTT (e.g., ~45ms)*

#### Step 2: Start heavy load on UE1
```bash
kubectl exec -n $NAMESPACE "$UE1_POD" -c nr-ue -- timeout 20 ping -f -c 5000 -s 1400 -I oaitun_ue1 12.1.1.1 &
```

#### Step 3: Measure UE2 latency WHILE UE1 is under load
```bash
kubectl exec -n $NAMESPACE "$UE2_POD" -c nr-ue -- ping -c 10 -i 0.2 -I oaitun_ue1 8.8.8.8
```
*Compare RTT with baseline - should be similar if slices are isolated*

---

### TEST B: Throughput Test

#### Throughput from UE1 (eMBB - high bandwidth)
```bash
# Ping flood test (estimating throughput)
kubectl exec -n $NAMESPACE "$UE1_POD" -c nr-ue -- ping -f -c 1000 -s 1400 -I oaitun_ue1 12.1.1.1
```
*The "time" value can be used to calculate throughput: (1000 × 1428 × 8) / time_ms / 1000 = Mbps*

#### Throughput from UE2 (uRLLC - lower bandwidth)
```bash
kubectl exec -n $NAMESPACE "$UE2_POD" -c nr-ue -- ping -f -c 1000 -s 1400 -I oaitun_ue1 12.2.1.1
```

**Expected:** eMBB should show higher throughput than uRLLC based on AMBR configuration.

---

### TEST C: Latency Test

#### Latency from UE1 (eMBB, 5QI=9)
```bash
kubectl exec -n $NAMESPACE "$UE1_POD" -c nr-ue -- ping -c 20 -i 0.1 -I oaitun_ue1 8.8.8.8
```

#### Latency from UE2 (uRLLC, 5QI=1)
```bash
kubectl exec -n $NAMESPACE "$UE2_POD" -c nr-ue -- ping -c 20 -i 0.1 -I oaitun_ue1 8.8.8.8
```

**Note:** In RF Simulator, latency differences may be minimal because internet RTT (~40ms) dominates. In real deployment, 5QI=1 would have lower latency.

---

## 8. Run Full Demo

```bash
./bp-flexric-slicing/demo_slicing.sh
```

This runs all tests automatically with formatted output.

---

## Architecture Summary

```
                    ┌─────────────────────────────────────────────────────────┐
                    │                      5G CORE                            │
                    │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐           │
                    │  │ NRF │  │ UDR │  │ UDM │  │AUSF │  │ AMF │           │
                    │  └─────┘  └─────┘  └─────┘  └─────┘  └──┬──┘           │
                    │                                         │               │
                    │            ┌────────────────────────────┴────────────┐  │
                    │            │                                          │  │
                    │    ┌───────▼───────┐                    ┌────────────▼─┐│
                    │    │  SMF-Slice1   │                    │  SMF-Slice2  ││
                    │    │  (SST=1,SD=1) │                    │  (SST=2,SD=1)││
                    │    └───────┬───────┘                    └──────┬───────┘│
                    │            │                                    │        │
                    │    ┌───────▼───────┐                    ┌──────▼───────┐│
                    │    │  UPF-Slice1   │                    │  UPF-Slice2  ││
                    │    │ 12.1.1.0/24   │                    │ 12.2.1.0/24  ││
                    │    └───────────────┘                    └──────────────┘│
                    └─────────────────────────────────────────────────────────┘
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    │                   gNB                      │
                    │         (Supports SST=1 and SST=2)         │
                    └─────────────────────┬─────────────────────┘
                                          │
              ┌───────────────────────────┴───────────────────────────┐
              │                                                        │
      ┌───────▼───────┐                                      ┌────────▼───────┐
      │     UE1       │                                      │      UE2       │
      │ IMSI: ...101  │                                      │  IMSI: ...102  │
      │ Slice 1 eMBB  │                                      │ Slice 2 uRLLC  │
      │ IP: 12.1.1.x  │                                      │ IP: 12.2.1.x   │
      └───────────────┘                                      └────────────────┘
```

---

## Quick Reference - Key Files

| Component | Configuration File |
|-----------|-------------------|
| AMF | `5G-oai-slicing/oai-5g-core/oai-amf/config.yaml` |
| SMF-Slice1 | `5G-oai-slicing/oai-5g-core/oai-smf-slice1/config.yaml` |
| SMF-Slice2 | `5G-oai-slicing/oai-5g-core/oai-smf-slice2/config.yaml` |
| UPF-Slice1 | `5G-oai-slicing/oai-5g-core/oai-upf-slice1/config.yaml` |
| UPF-Slice2 | `5G-oai-slicing/oai-5g-core/oai-upf-slice2/config.yaml` |
| gNB | `5G-oai-slicing/oai-gnb/config.yaml` |
| UE1 (eMBB) | `5G-oai-slicing/oai-nr-ue-slice1/values.yaml` |
| UE2 (uRLLC) | `5G-oai-slicing/oai-nr-ue-slice2/values.yaml` |
| Deployment Script | `5G-oai-slicing/start_slicing.sh` |
| Demo Script | `5G-oai-slicing/demo_slicing.sh` |
