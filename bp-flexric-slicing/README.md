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

## Suggestions for a good README

Every project is different, so consider which of these sections apply to yours. The sections used in the template are suggestions for most open source projects. Also keep in mind that while a README can be too long and detailed, too long is better than too short. If you think your README is too long, consider utilizing another form of documentation rather than cutting out information.

## Name
Choose a self-explaining name for your project.

## Description
Let people know what your project can do specifically. Provide context and add a link to any reference visitors might be unfamiliar with. A list of Features or a Background subsection can also be added here. If there are alternatives to your project, this is a good place to list differentiating factors.

## Badges
On some READMEs, you may see small images that convey metadata, such as whether or not all the tests are passing for the project. You can use Shields to add some to your README. Many services also have instructions for adding a badge.

## Visuals
Depending on what you are making, it can be a good idea to include screenshots or even a video (you'll frequently see GIFs rather than actual videos). Tools like ttygif can help, but check out Asciinema for a more sophisticated method.

## Installation
Within a particular ecosystem, there may be a common way of installing things, such as using Yarn, NuGet, or Homebrew. However, consider the possibility that whoever is reading your README is a novice and would like more guidance. Listing specific steps helps remove ambiguity and gets people to using your project as quickly as possible. If it only runs in a specific context like a particular programming language version or operating system or has dependencies that have to be installed manually, also add a Requirements subsection.

## Usage
Use examples liberally, and show the expected output if you can. It's helpful to have inline the smallest example of usage that you can demonstrate, while providing links to more sophisticated examples if they are too long to reasonably include in the README.

## Support
Tell people where they can go to for help. It can be any combination of an issue tracker, a chat room, an email address, etc.

## Roadmap
If you have ideas for releases in the future, it is a good idea to list them in the README.

## Contributing
State if you are open to contributions and what your requirements are for accepting them.

For people who want to make changes to your project, it's helpful to have some documentation on how to get started. Perhaps there is a script that they should run or some environment variables that they need to set. Make these steps explicit. These instructions could also be useful to your future self.

You can also document commands to lint the code or run tests. These steps help to ensure high code quality and reduce the likelihood that the changes inadvertently break something. Having instructions for running tests is especially helpful if it requires external setup, such as starting a Selenium server for testing in a browser.

## Authors and acknowledgment
Show your appreciation to those who have contributed to the project.

## License
For open source projects, say how it is licensed.

## Project status
If you have run out of energy or time for your project, put a note at the top of the README saying that development has slowed down or stopped completely. Someone may choose to fork your project or volunteer to step in as a maintainer or owner, allowing your project to keep going. You can also make an explicit request for maintainers.
