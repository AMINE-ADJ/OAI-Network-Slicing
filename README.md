<!-- # 5G/KPM xApp Experimentation Platform

This project implements a complete 5G experimentation platform using OAI (OpenAirInterface) and FlexRIC, designed for developing and monitoring KPM (Key Performance Metric) xApps.

## Project Overview

The system deploys a full 5G network (Core, RAN, UE) and a Near-RT RIC (FlexRIC) on a Kubernetes cluster (Minikube). It includes a custom xApp for monitoring real-time network metrics.

### Components

- **OAI 5G Core**: AMF, SMF, UPF, NRF, UDM, UDR, AUSF, MySQL.
- **FlexRIC**: Near-RT RIC with E2 interface support.
- **OAI gNB**: 5G Base Station (simulated RF).
- **OAI NR-UE**: 5G User Equipment (simulated).
- **KPM xApp**: Custom xApp for metric collection.

## Quick Start

### 1. Prerequisite
- Linux OS (Ubuntu/Arch/Fedora)
- Minikube & Docker
- Ansible (for deployment orchestration)

### 2. Deploy Network
To deploy the entire 5G infrastructure (fresh start):

```bash
./start_5g.sh
```

This script will:
1. Start/Check Minikube.
2. Clean up any stale deployments.
3. specific Ansible playbook to deploy all components in the correct order.

_Deployment takes approximately 3-5 minutes._

### 3. Verify Deployment
Check the status of the pods:

```bash
kubectl get pods -n blueprint -w
```
Wait until all pods (Core, gNB, UE, FlexRIC) are in `Running` state.

## Data Collection

To generate traffic (iperf3) and collect KPM metrics:

```bash
./start-collection.sh <duration_in_seconds> <bandwidth>
```

**Example:** Run for 60 seconds with 20Mbps traffic:
```bash
./start-collection.sh 60 20M
```

This script handles:
1. Verifying UPF and UE connectivity.
2. Auto-installing `iperf3` on the UPF if missing.
3. Starting the xApp monitor.
4. Generating traffic from UE -> UPF.
5. Saving results to `cell_xapp_monitor/data/`.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Minikube                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                   5G Core Network                    │   │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐   │   │
│  │  │ NRF │ │ AMF │ │ SMF │ │ UPF │ │ UDM │ │ UDR │   │   │
│  │  └─────┘ └──┬──┘ └──┬──┘ └──┬──┘ └─────┘ └─────┘   │   │
│  └─────────────┼───────┼───────┼─────────────────────────┘   │
│                │       │       │                            │
│  ┌─────────────┼───────┼───────┼─────────────────────────┐   │
│  │             │    FlexRIC    │                         │   │
│  │        ┌────┴───────┴───────┴────┐                    │   │
│  │        │      Near-RT RIC        │◄──── xApps        │   │
│  │        └────────────┬────────────┘                    │   │
│  │                     │ E2                                 │
│  └─────────────────────┼─────────────────────────────────┘   │
│                        │                                    │
│  ┌─────────────────────┼─────────────────────────────────┐   │
│  │              ┌──────▼───┐                             │   │
│  │              │   gNB    │ (RF Simulator)              │   │
│  │              └────┬─────┘                             │   │
│  │                   │                                   │   │
│  │              ┌────▼─────┐                             │   │
│  │              │    UE    │ (IP: 12.1.1.2)              │   │
│  │              └──────────┘                             │   │
│  └───────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

- `start_5g.sh`: Main deployment script.
- `start-collection.sh`: Traffic generation and data collection script.
- `roles/`: Ansible roles for component deployment.
- `inventories/`: Ansible inventory configurations.
- `cell_xapp_monitor/`: Python scripts for xApp monitoring and data storage. -->



# 5G Network Slicing with OAI and FlexRIC

This project deploys a complete 5G network with **network slicing** using OpenAirInterface (OAI) components on Kubernetes (minikube).

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              5G Core Network                                │
│  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────┐  ┌───────┐          │
│  │ MySQL │  │  NRF  │  │  UDR  │  │  UDM  │  │ AUSF  │  │  AMF  │          │
│  └───────┘  └───────┘  └───────┘  └───────┘  └───────┘  └───────┘          │
│                                                                             │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐          │
│  │      Slice 1 (eMBB)         │  │      Slice 2 (uRLLC)        │          │
│  │  SST=1, SD=1                │  │  SST=2, SD=1                │          │
│  │  ┌───────────┐ ┌──────────┐ │  │  ┌───────────┐ ┌──────────┐ │          │
│  │  │SMF-slice1 │ │UPF-slice1│ │  │  │SMF-slice2 │ │UPF-slice2│ │          │
│  │  └───────────┘ └──────────┘ │  │  └───────────┘ └──────────┘ │          │
│  │  IP Pool: 12.1.1.0/24       │  │  IP Pool: 12.2.1.0/24       │          │
│  └─────────────────────────────┘  └─────────────────────────────┘          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                              ┌─────┴─────┐
                              │  FlexRIC  │ (E2 Interface)
                              └─────┬─────┘
                                    │
┌───────────────────────────────────┴─────────────────────────────────────────┐
│                              RAN (gNB)                                      │
│                         RF Simulator Mode                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
              ┌─────┴─────┐                   ┌─────┴─────┐
              │ UE Slice1 │                   │ UE Slice2 │
              │ SST=1,SD=1│                   │ SST=2,SD=1│
              │ 12.1.1.x  │                   │ 12.2.1.x  │
              └───────────┘                   └───────────┘
```

## Prerequisites

- **minikube** installed and running
- **kubectl** configured
- **helm** v3+
- At least **8GB RAM** and **4 CPUs** for minikube

### Start minikube

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
```

## Quick Start

### 1. Deploy the entire 5G slicing infrastructure

```bash
cd bp-flexric-slicing
./start_slicing.sh deploy
```

This will deploy in order:
1. Core Network (MySQL, NRF, UDR, UDM, AUSF, AMF)
2. Slice 1 components (SMF-slice1, UPF-slice1)
3. Slice 2 components (SMF-slice2, UPF-slice2)
4. FlexRIC (E2 controller)
5. gNB (with E2 agent)
6. UE for Slice 1
7. UE for Slice 2

### 2. Check deployment status

```bash
./start_slicing.sh status
```

Expected output: **14 pods running** in the `blueprint` namespace.

### 3. Verify connectivity

```bash
./start_slicing.sh verify
```

This checks:
- UE1 has IP in 12.1.1.0/24 range
- UE2 has IP in 12.2.1.0/24 range
- Both UEs can ping their respective UPFs

### 4. Run slicing tests

```bash
./start_slicing.sh test
```

This validates:
- UE1 is correctly assigned to Slice 1
- UE2 is correctly assigned to Slice 2
- Cross-slice isolation is maintained

### 5. Run performance benchmarks

```bash
./start_slicing.sh benchmark
```

This runs:
- **Latency tests**: Ping from each UE
- **Throughput tests**: iperf3 UDP downlink (if available)
- **Fairness tests**: Cross-slice interference measurement

## Available Commands

| Command | Description |
|---------|-------------|
| `./start_slicing.sh deploy` | Deploy entire infrastructure |
| `./start_slicing.sh cleanup` | Remove all deployed components |
| `./start_slicing.sh status` | Show pod status |
| `./start_slicing.sh core` | Deploy only core network |
| `./start_slicing.sh ran` | Deploy only gNB |
| `./start_slicing.sh ue` | Deploy only UEs |
| `./start_slicing.sh flexric` | Deploy only FlexRIC |
| `./start_slicing.sh subscribers` | Add subscribers to database |
| `./start_slicing.sh verify` | Verify UE connectivity |
| `./start_slicing.sh test` | Run slicing validation tests |
| `./start_slicing.sh benchmark` | Run performance benchmarks |

## Manual Testing

### Check UE IP addresses

```bash
# UE1 (Slice 1) - should get 12.1.1.x
kubectl -n blueprint exec -it $(kubectl -n blueprint get pods -l app.kubernetes.io/name=oai-nr-ue-slice1 -o jsonpath='{.items[0].metadata.name}') -- ip addr show oaitun_ue1

# UE2 (Slice 2) - should get 12.2.1.x
kubectl -n blueprint exec -it $(kubectl -n blueprint get pods -l app.kubernetes.io/name=oai-nr-ue-slice2 -o jsonpath='{.items[0].metadata.name}') -- ip addr show oaitun_ue1
```

### Test connectivity from UEs

```bash
# From UE1
kubectl -n blueprint exec -it $(kubectl -n blueprint get pods -l app.kubernetes.io/name=oai-nr-ue-slice1 -o jsonpath='{.items[0].metadata.name}') -- ping -c 5 12.1.1.1

# From UE2
kubectl -n blueprint exec -it $(kubectl -n blueprint get pods -l app.kubernetes.io/name=oai-nr-ue-slice2 -o jsonpath='{.items[0].metadata.name}') -- ping -c 5 12.2.1.1
```

### View logs

```bash
# AMF logs
kubectl -n blueprint logs -f deployment/oai-amf

# SMF Slice 1 logs
kubectl -n blueprint logs -f deployment/oai-smf-slice1

# gNB logs
kubectl -n blueprint logs -f deployment/oai-gnb

# FlexRIC logs
kubectl -n blueprint logs -f deployment/oai-flexric
```

## Network Slice Configuration

### Slice 1 (eMBB - Enhanced Mobile Broadband)
- **S-NSSAI**: SST=1, SD=1
- **DNN**: oai
- **IP Pool**: 12.1.1.0/24
- **Use Case**: High throughput applications

### Slice 2 (uRLLC - Ultra-Reliable Low-Latency)
- **S-NSSAI**: SST=2, SD=1
- **DNN**: oai
- **IP Pool**: 12.2.1.0/24
- **Use Case**: Low latency applications

## Subscriber Configuration

Subscribers are pre-configured in the MySQL database:

| IMSI | Slice | Key | OPC |
|------|-------|-----|-----|
| 001010000000001 | SST=1, SD=1 | fec86ba6eb707ed08905757b1bb44b8f | C42449363BBAD02B66D16BC975D77CC1 |
| 001010000000002 | SST=2, SD=1 | fec86ba6eb707ed08905757b1bb44b8f | C42449363BBAD02B66D16BC975D77CC1 |

## Troubleshooting

### Pods not starting
```bash
kubectl -n blueprint describe pod <pod-name>
kubectl -n blueprint logs <pod-name>
```

### UE not getting IP
1. Check SMF logs for PDU session errors
2. Verify UPF is registered with NRF
3. Check AMF logs for registration status

```bash
kubectl -n blueprint logs deployment/oai-smf-slice1 | grep -i "pdu\|error"
kubectl -n blueprint logs deployment/oai-amf | grep -i "registration"
```

### FlexRIC not connecting to gNB
```bash
kubectl -n blueprint logs deployment/oai-flexric | grep -i "e2\|connect"
kubectl -n blueprint logs deployment/oai-gnb | grep -i "e2\|flexric"
```

### Cleanup and redeploy
```bash
./start_slicing.sh cleanup
sleep 10
./start_slicing.sh deploy
```

## Project Structure

```
bp-flexric-slicing/
├── start_slicing.sh          # Main deployment script
├── oai-5g-core/              # Core network Helm charts
│   ├── mysql/                # Database with subscriber info
│   ├── oai-nrf/              # Network Repository Function
│   ├── oai-udr/              # Unified Data Repository
│   ├── oai-udm/              # Unified Data Management
│   ├── oai-ausf/             # Authentication Server Function
│   ├── oai-amf/              # Access & Mobility Management
│   ├── oai-smf-slice1/       # Session Management (Slice 1)
│   ├── oai-smf-slice2/       # Session Management (Slice 2)
│   ├── oai-upf-slice1/       # User Plane Function (Slice 1)
│   └── oai-upf-slice2/       # User Plane Function (Slice 2)
├── oai-gnb/                  # gNB with E2 agent
├── oai-nr-ue-slice1/         # UE for Slice 1
├── oai-nr-ue-slice2/         # UE for Slice 2
└── oai-flexric/              # FlexRIC E2 controller
```

## References

- [OAI 5G Core Documentation](https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed)
- [OAI RAN Documentation](https://gitlab.eurecom.fr/oai/openairinterface5g)
- [FlexRIC Documentation](https://gitlab.eurecom.fr/mosaic5g/flexric)
- [3GPP Network Slicing](https://www.3gpp.org/technologies/keywords-acronyms/network-slicing)

## License

This project uses OAI components which are licensed under OAI Public License V1.1.

