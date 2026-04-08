# netop-tools

**netop-tools** provides configuration automation for **NVIDIA Network Operator** in Kubernetes clusters. It simplifies deployment and management of RDMA networking, SR-IOV Virtual Functions (VFs), IPoIB, Macvlan, and HostDev network configurations for AI/ML workloads on bare metal and virtualized Kubernetes environments.

---

## Table of Contents

- [Quick Start](#quick-start)
- [HOW-TO Guide](#how-to-guide)
  - [Step 1: Environment Setup](#step-1-environment-setup)
  - [Step 2: Use Case Selection](#step-2-use-case-selection)
  - [Step 3: Configuration](#step-3-configuration)
  - [Step 4: K8s Cluster Bootstrap](#step-4-k8s-cluster-bootstrap)
  - [Step 5: Network Operator Installation](#step-5-network-operator-installation)
  - [Step 6: Network Configuration and Deployment](#step-6-network-configuration-and-deployment)
  - [Step 7: Application Pod Deployment](#step-7-application-pod-deployment)
  - [Step 8: Verification and Status](#step-8-verification-and-status)
  - [Step 9: RDMA Testing](#step-9-rdma-testing)
  - [Step 10: Device Management](#step-10-device-management)
  - [Step 11: Node Management](#step-11-node-management)
  - [Step 12: Diagnostics and Must-Gather](#step-12-diagnostics-and-must-gather)
  - [Step 13: Upgrade](#step-13-upgrade)
  - [Step 14: Restart and Recovery](#step-14-restart-and-recovery)
  - [Step 15: Cleanup and Uninstall](#step-15-cleanup-and-uninstall)
- [Python CLI](#python-cli)
- [Container Registry Tools](#container-registry-tools)
- [RDMA Debug Containers](#rdma-debug-containers)
- [ARP Tools](#arp-tools)
- [Testing Framework](#testing-framework)
- [Configuration Reference](#configuration-reference)
- [Platform Configs](#platform-configs)
- [Directory Layout](#directory-layout)

---

## Quick Start

For experienced users who already have a K8s cluster running:

```bash
git clone https://github.com/Mellanox/netop-tools.git
cd netop-tools
source NETOP_ROOT_DIR.sh
cp config/dell/global_ops_user.cfg.Dell.Poweredge.H100.H200 global_ops_user.cfg
# Edit global_ops_user.cfg for your environment
export CREATE_CONFIG_ONLY=0
./install/ins-network-operator.sh
kubectl get pods -A
```

---

## HOW-TO Guide

### Step 1: Environment Setup

#### 1.1 Clone and initialize

```bash
git clone https://github.com/Mellanox/netop-tools.git
cd netop-tools
source NETOP_ROOT_DIR.sh    # Exports NETOP_ROOT_DIR=$(pwd)
```

`NETOP_ROOT_DIR` must be set before running any other script.

#### 1.2 Select and customize a platform config

Copy a pre-built config for your hardware platform:

```bash
# Example: Dell PowerEdge with H100/H200
cp config/dell/global_ops_user.cfg.Dell.Poweredge.H100.H200 global_ops_user.cfg

# Example: DGX B200 with BCM
cp config/dgx/global_ops_user.cfg.DGXB200.bcm global_ops_user.cfg

# Example: DGX GB200 (ConnectX-7, 16 VFs)
cp config/dgx/global_ops_user.cfg.DGXGB200.bcm global_ops_user.cfg

# Example: DGX GB300 (ConnectX-8, 16 VFs, NIC config enabled)
cp config/dgx/global_ops_user.cfg.DGXGB300.bcm global_ops_user.cfg

# Example: OCI cloud
cp config/oci/global_ops_user.cfg.oci global_ops_user.cfg
```

Edit `global_ops_user.cfg` to match your environment. Key settings to verify:

- `NETOP_NETLIST` — PCI addresses or interface names of your NVIDIA NICs
- `NUM_VFS` — number of SR-IOV virtual functions per device
- `NETOP_NETWORK_RANGE` — CIDR for the secondary RDMA network
- `DEVICE_TYPES` — NIC model array (e.g., `connectx-7`)
- `CREATE_CONFIG_ONLY` — set to `0` to actually deploy (default `1` generates YAML only)

#### 1.3 Load configuration

```bash
source global_ops.cfg
```

This sources `global_ops_user.cfg` first, then `usecase/${USECASE}/netop.cfg`, applying the configuration cascade:

**Priority** (highest to lowest): ENV vars > `global_ops_user.cfg` > `usecase/{USECASE}/netop.cfg` > `global_ops.cfg` defaults

---

### Step 2: Use Case Selection

#### 2.1 Available use cases

| Use Case | Description | VFs | Device ID Format |
|---|---|---|---|
| `sriovnet_rdma` | SR-IOV Ethernet with RDMA (default) | 8 | PCI BDF: `0000:08:00.0` |
| `sriovibnet_rdma` | SR-IOV InfiniBand with RDMA | 8 | IB interface: `ibs0f1` |
| `hostdev_rdma_sriov` | HostDevice passthrough with SR-IOV | 8 | Multi-PCI: `0000:07:00.0,0000:08:00.0` |
| `ipoib_rdma_shared_device` | IPoIB with shared RDMA device | 0 | IB interface: `ibs0f0` |
| `macvlan_rdma_shared_device` | Macvlan with shared RDMA device | 0 | Ethernet interface: `ens2f0np0` |

#### 2.2 Set the use case

```bash
# Set via environment variable before sourcing config
export USECASE="sriovnet_rdma"
source global_ops.cfg

# Or switch use case at any time
./setuc.sh sriovnet_rdma
```

`setuc.sh` creates a symlink `uc/` pointing to `usecase/${USECASE}/`. Generated YAML files are written into this directory.

#### 2.3 NETOP_NETLIST format

The device list is the most critical per-platform setting. Format:

```
NETOP_NETLIST=( device_index,field2,field3,device_identifier )
```

| Field | Description |
|---|---|
| `device_index` | Alphabetic label (`a`, `b`, `c`, ...). Becomes resource suffix: `sriov_resource_a` |
| `field2` | Reserved (leave empty) |
| `field3` | `HCAMAX` for shared device use cases, empty for SR-IOV |
| `device_identifier` | PCI BDF, IB interface name, or Ethernet interface name (use-case-dependent) |

Examples:

```bash
# SR-IOV Ethernet (PCI BDF addresses)
NETOP_NETLIST=( a,,,0000:08:00.0 b,,,0000:86:00.1 )

# SR-IOV InfiniBand (IB interface names)
NETOP_NETLIST=( a,,,ibs0f1 b,,,ibs1f1 )

# HostDevice (multiple PCI devices per entry)
NETOP_NETLIST=( a,,,0000:07:00.0,0000:08:00.0 b,,,0000:09:00.0,0000:0a:00.0 )

# IPoIB shared device (field3 = HCAMAX)
NETOP_NETLIST=( a,,63,ibs0f0 b,,63,ibs0f1 )

# Macvlan shared device (field3 = HCAMAX)
NETOP_NETLIST=( a,,63,ens2f0np0 b,,63,ens3f0np0 )
```

---

### Step 3: Configuration

#### 3.1 Feature flags

| Variable | Default | Description |
|---|---|---|
| `OFED_ENABLE` | `true` | Deploy containerized DOCA OFED driver. Set `false` if using kernel OFED. |
| `NFD_ENABLE` | `true` | Node Feature Discovery. Disable if GPU-operator already runs NFD. |
| `NIC_CONFIG_ENABLE` | `false` | NIC Configuration Operator for firmware parameter tuning. |
| `MAINTENANCE_OPERATOR_ENABLE` | `true` | Maintenance Operator for node maintenance windows. |
| `NIC_FD_ENABLE` | `false` | NIC Feature Discovery. |
| `ENABLE_NFSRDMA` | `false` | NFS over RDMA support. |
| `FW_UPGRADE_ENABLE` | `false` | Firmware upgrade orchestration. |
| `RDMASHAREDMODE` | `true` | `true`: all RDMA devices visible in pod. `false`: only allocated devices. |
| `SBRMODE` | `false` | Source-Based Routing for E/W RDMA traffic. |

#### 3.2 SR-IOV feature gates

| Variable | Default | Description |
|---|---|---|
| `FG_PARALLEL_NIC_CONFIG` | `true` | Parallelize NIC configuration (faster). |
| `FG_RESOURCE_INJECTOR_MATCH` | `false` | Match condition for resource injection. |
| `FG_MLNX_FW_RESET` | `false` | Mellanox firmware reset capability. |
| `METRICS_EXPORTER` | `false` | Prometheus metrics exporter. |
| `MANAGE_SW_BRIDGE` | `false` | Manage software bridges. |

#### 3.3 IPAM options

| Type | Variable Setting | Best For | Description |
|---|---|---|---|
| **nv-ipam** | `IPAM_TYPE="nv-ipam"` | Large clusters (>60 nodes) | NVIDIA native IPAM. Supports `IPPool` and `CIDRPool` types via `NVIPAM_POOL_TYPE`. |
| **whereabouts** | `IPAM_TYPE="whereabouts"` | Small clusters (<60 nodes) | Community CNI IPAM. Uses Kubernetes ConfigMaps. |
| **dhcp** | `IPAM_TYPE="dhcp"` | External DHCP server | Delegates IP allocation to external DHCP daemon. |

For nv-ipam, choose pool type:

```bash
export NVIPAM_POOL_TYPE="IPPool"    # Per-node IP blocks (default)
export NVIPAM_POOL_TYPE="CIDRPool"  # Per-node CIDR subnets
```

#### 3.4 Combined mode (BCM)

For multi-device platforms (e.g., DGX with 8 NICs), combined mode merges per-device YAML files into single files:

```bash
export NETOP_BCM_CONFIG="true"
```

| Standard Mode | Combined Mode |
|---|---|
| `network.yaml` | `combined-sriovnet.yaml` |
| `ippool.yaml` | `combined-ippools.yaml` |
| `node-policy.yaml` | `combined-node-policy.yaml` |
| `values.yaml` | `netop-values.yaml` |

Combined mode also disables `resourceInjectorMatchCondition`, `metricsExporter`, and `manageSoftwareBridges` feature gates.

#### 3.5 Scalable units (multi-tenant)

Scalable units allow separate IP pools and network definitions for different pod groups:

```bash
# Single tenant (default)
NETOP_SULIST=( "su-1" )

# Multi-tenant
NETOP_SULIST=( "su-runai" "su-ml" "su-inference" )
```

Each SU generates its own IPPool and network CRDs per device. Resource naming pattern: `sriovnet-pool-{device}-{su}`.

---

### Step 4: K8s Cluster Bootstrap

Skip this step if you already have a running Kubernetes cluster.

#### 4.1 Full master node setup

```bash
# One-command installation (installs master, init, calico)
./ins-k8.sh
```

Or step by step using `install/ins-k8master.sh`:

```bash
# Install K8s master components (Helm, K8s packages, Docker/containerd)
./install/ins-k8master.sh master

# Initialize cluster with kubeadm
./install/ins-k8master.sh init

# Install Calico CNI
./install/ins-k8master.sh calico
```

Alternative one-shot script:

```bash
./startk8master.sh
```

#### 4.2 Join worker nodes

On each worker node:

```bash
source NETOP_ROOT_DIR.sh
source global_ops.cfg
./install/ins-k8worker.sh
```

Label and configure workers from the master:

```bash
./install/ins-k8master.sh worker <NODENAME>
```

#### 4.3 Platform-specific installers

Ubuntu:

```bash
./install/ubuntu/ins-k8base.sh     # K8s prerequisites (containerd, kubeadm, kubelet, kubectl)
./install/ubuntu/ins-k8repo.sh     # Add Kubernetes APT repository
./install/ubuntu/ins-docker.sh     # Docker CE installation
./install/ubuntu/ins-go.sh         # Go language
./install/ubuntu/ins-kubectx.sh    # kubectx/kubens utilities
```

RHEL/CentOS:

```bash
./install/rhel/ins-k8base.sh       # K8s prerequisites (kubeadm, kubelet, kubectl)
./install/rhel/ins-docker.sh       # Docker installation
./install/rhel/ins-go.sh           # Go language
```

#### 4.4 Component installers

```bash
./install/ins-helm.sh              # Helm package manager
./install/ins-helm-repo.sh         # Add NVIDIA Helm repository
./install/ins-calico.sh            # Calico CNI
./install/ins-calicoctl.sh         # Calico CLI tools
./install/ins-multus.sh            # Multus meta-plugin (secondary networks)
./install/ins-metrics.sh           # Prometheus metrics
./install/ins-nerdctl.sh           # nerdctl (containerd CLI)
```

#### 4.5 Verify cluster readiness

```bash
kubectl get nodes
./install/wait-k8sready.sh         # Polls until cluster is ready
./install/readytest.sh             # Readiness validation
```

---

### Step 5: Network Operator Installation

#### 5.1 Install the Network Operator

```bash
./install/ins-network-operator.sh
```

This orchestrates the full deployment pipeline:

```
ins-network-operator.sh
  ├─ setuc.sh                      → Validate + create uc/ symlink
  ├─ install/mksecret.sh           → Image pull secret (NGC credentials)
  ├─ ops/mk-config.sh              → Generate all YAML config:
  │   ├─ ops/mk-values.sh          → Helm values.yaml
  │   ├─ ops/mk-nic-cluster-policy.sh → NicClusterPolicy CRD
  │   ├─ ops/mk-network-cr.sh      → Network + IPAM CRDs
  │   ├─ ops/mk-sriov-node-pool.sh → SriovNetworkPoolConfig
  │   └─ ops/mk-nic-config.sh      → NIC config (if NIC_CONFIG_ENABLE=true)
  ├─ helm install network-operator → Deploy operator via Helm
  ├─ install/applycrds.sh          → Apply base CRDs
  └─ ops/apply-network-cr.sh       → Apply network resources
```

#### 5.2 Config-only mode (dry run)

By default, `CREATE_CONFIG_ONLY=1` generates YAML without deploying. To actually deploy:

```bash
export CREATE_CONFIG_ONLY=0
./install/ins-network-operator.sh
```

#### 5.3 Python CLI alternative

```bash
python3 python_tools/netop_tools.py install helm
python3 python_tools/netop_tools.py install chart
python3 python_tools/netop_tools.py install network-operator
python3 python_tools/netop_tools.py install calico
python3 python_tools/netop_tools.py install crds
python3 python_tools/netop_tools.py install wait k8s
```

#### 5.4 Alternative installation methods

```bash
./install/ins-network-operator-default.sh    # Default/stable release
./install/ins-network-operator-beta.sh       # Beta/staging release
```

---

### Step 6: Network Configuration and Deployment

#### 6.1 Generate all configuration

```bash
cd usecase/${USECASE}
${NETOP_ROOT_DIR}/ops/mk-config.sh
```

`mk-config.sh` calls the following in sequence:

| Script | Output | Description |
|---|---|---|
| `ops/mk-values.sh` | `values.yaml` | Helm values (feature flags, image versions, operator config) |
| `ops/mk-nic-cluster-policy.sh` | `NicClusterPolicy.yaml` | NicClusterPolicy CRD (OFED, NFD, device plugins) |
| `ops/mk-network-cr.sh` | `network.yaml` + `ippool-*.yaml` | Network + IPAM CRDs per device |
| `ops/mk-sriov-node-pool.sh` | `sriov-node-pool-config.yaml` | SR-IOV VF allocation policy |
| `ops/mk-nic-config.sh` | `nic-config-crd-{type}.yaml` | NIC firmware config (if enabled) |

#### 6.2 Apply network resources

```bash
${NETOP_ROOT_DIR}/ops/apply-network-cr.sh
```

This applies in order:
1. SriovNetworkNodePolicy CRDs (SR-IOV use cases)
2. Network CRDs (SriovNetwork, SriovIBNetwork, HostDeviceNetwork, etc.)
3. IPAM CRDs (IPPool or CIDRPool)

#### 6.3 Delete network resources

```bash
${NETOP_ROOT_DIR}/ops/delete-network-cr.sh
```

Removes all network CRDs in reverse order.

#### 6.4 Subnet generation utility

```bash
# Generate subnets from a CIDR range
./ops/generate_subnets.sh <IP/netmask> <count> [gateway_pattern]

# Examples:
./ops/generate_subnets.sh 192.170.0.0/24 3
# Output: 192.170.0.0/24 Gateway: 192.170.0.1
#         192.170.1.0/24 Gateway: 192.170.1.1
#         192.170.2.0/24 Gateway: 192.170.2.1

./ops/generate_subnets.sh 192.170.0.0/24 2 192.170.0.1
# Output: 192.170.0.0/24 Gateway: 192.170.0.1
#         192.170.1.0/24 Gateway: 192.170.1.1
```

---

### Step 7: Application Pod Deployment

#### 7.1 Create a test pod

```bash
# Usage: ops/mk-app.sh <podname> [num_of_pods] [app_namespace] [worker_node]
${NETOP_ROOT_DIR}/ops/mk-app.sh test
${NETOP_ROOT_DIR}/ops/mk-app.sh test 2                          # 2 replicas
${NETOP_ROOT_DIR}/ops/mk-app.sh test 2 default                  # Explicit namespace
${NETOP_ROOT_DIR}/ops/mk-app.sh test 1 default worker-node-01   # Pin to specific node
```

This generates pod YAML in `usecase/${USECASE}/apps/` with:
- Secondary network annotations (one per device per SU)
- GPU resource requests (if `NUM_GPUS > 0`)
- RDMA device resource requests (per device in `NETOP_NETLIST`)
- Privileged security context with `IPC_LOCK` capability

#### 7.2 Deploy the pod

```bash
${NETOP_ROOT_DIR}/ops/run-app.sh test
```

Applies the generated YAML via `kubectl apply`.

#### 7.3 Verify pod status

```bash
kubectl get pods -A
kubectl describe pod test-1
```

---

### Step 8: Verification and Status

#### 8.1 Overall network status

```bash
# Comprehensive network status (attachment definitions, NicClusterPolicy, RDMA devices, IP pools)
./ops/getnetwork.sh

# Pod network attachment status
./ops/getnetworkstatus.sh

# Pod-level network details
./ops/getpodnetworkstatus.sh

# Python CLI alternative (JSON output)
python3 python_tools/netop_tools.py ops network status
```

#### 8.2 IPAM status

```bash
# Node IPAM annotations (IP block allocations)
./ops/checkipam.sh
# Python CLI: python3 python_tools/netop_tools.py ops check ipam

# IP pool usage on a specific node
./ops/checkippool.sh <NODENAME>

# List IP pools
./ops/getippool.sh
./ops/getippool-lst.sh
./ops/getallocatedip.sh

# CIDR pools
./ops/getcidrpool.sh
./ops/getcidrpools.sh
./ops/getcidrpool-lst.sh
```

#### 8.3 SR-IOV status

```bash
# SR-IOV synchronization state
./ops/checksriovstate.sh
# Python CLI: python3 python_tools/netop_tools.py ops check sriov

# Wait for SR-IOV sync to complete (can take up to 10 minutes)
./ops/syncsriov.sh

# SR-IOV node policies
./ops/getsriovnodepolicy.sh

# SR-IOV node state
./ops/getsriovnodestate.sh
```

#### 8.4 NIC and cluster policy status

```bash
# NicClusterPolicy CRD
./ops/getNicClusterPolicy.sh

# Network attachment definitions
./ops/get-network-attach-defs.sh

# Node resources (allocatable capacity)
./ops/get-noderesources.sh

# Custom resource definitions
./ops/getcrds.sh

# All resources in a namespace
./ops/kubectlgetall.sh [NAMESPACE]

# API resources discovery
./ops/getresource.sh <NAMESPACE>

# Service endpoints
./ops/getendpoints.sh
```

---

### Step 9: RDMA Testing

#### 9.1 Verify RDMA capability

```bash
# Check RDMA kernel modules are loaded
./rdmatest/check_rdma.sh

# Enumerate RDMA devices
./rdmatest/get_rdma_dev.sh

# Disable PCI ACS for peer-to-peer RDMA (run on bare metal)
./rdmatest/disable_acs.sh
./rdmatest/disable_acs_ext.sh    # Extended topology variant
```

#### 9.2 RDMA bandwidth tests (inside pods)

RoCE (RDMA over Converged Ethernet):

```bash
# On server pod:
./rdmatest/rocesrv.sh

# On client pod:
./rdmatest/roceclnt.sh
```

InfiniBand:

```bash
# On server pod:
./rdmatest/rdmasrv.sh            # Starts ib_send_bw server

# On client pod:
./rdmatest/rdmaclnt.sh           # Runs ib_send_bw client
```

GPU Direct RDMA:

```bash
# On server pod:
./rdmatest/gdrsrv.sh             # GPU Direct RDMA server

# On client pod:
./rdmatest/gdrclt.sh             # GPU Direct RDMA client
```

General InfiniBand bandwidth test:

```bash
./rdmatest/ib_bw_test.sh
```

#### 9.3 RDMA environment setup

```bash
./rdmatest/rdmasetup.sh          # Setup RDMA environment inside test pod
./rdmatest/podports.sh           # List port bindings in test pod
./rdmatest/podcprdma.sh          # Pod-to-pod RDMA connectivity test
```

#### 9.4 Performance testing (rdmatools/)

```bash
# Standard perftest (ib_send_bw, ib_write_bw, etc.)
./rdmatools/perftest.sh

# Perftest with CUDA GPU memory buffers
./rdmatools/perftestcuda.sh
./rdmatools/perftestenv.sh       # Set environment for GPU-accelerated tests

# RDMA diagnostics
./rdmatools/rdmadebug.sh
./rdmatools/getrdmanet.sh        # List RDMA-capable network devices
./rdmatools/show_gids            # Display InfiniBand Global IDs
./rdmatools/k8s-netdev-mapping.sh # Map K8s pod network devices to GPU/VF allocation

# RDMA traffic capture
./rdmatools/tcpdumprdma.sh

# Sysctl tuning for RDMA
./rdmatools/sysctl_config.sh
```

---

### Step 10: Device Management

#### 10.1 SR-IOV virtual function (VF) configuration

```bash
# Set VFs on PCI devices (run on worker node)
./setvfs.sh <NUM_VFS> <BDF1> [BDF2] ...
# Example: ./setvfs.sh 8 0000:08:00.0 0000:86:00.1

# Alternative VF setter
./rundev.sh <NUM_VFS> <BDF1> [BDF2] ...

# Set VFs via ops script
./ops/setnumvfs.sh

# Query current VF count
./ops/getnumvfs.sh
```

#### 10.2 PCI device information

```bash
./ops/getpci.sh                  # List PCI devices
./ops/getpciid.sh                # Show PCI vendor IDs
./ops/grabpci.sh                 # Extract PCI configuration details
./ops/pcislotparse.sh            # Parse PCI slot/BDF layout
./ops/devlist.sh                 # List network devices
```

#### 10.3 Link speed control

```bash
# Force link speed (disables auto-negotiation)
./ops/force_link_speed.sh <DEV> <SPEED> <XVAL>

# Supported speeds: 10G, 25G, 40G, 50G, 100G, 200G, 400G, 800G
# XVAL must match speed: 1X, 2X, 4X, 8X

# Examples:
./ops/force_link_speed.sh mlx5_0 100G 2X
./ops/force_link_speed.sh mlx5_0 400G 4X

# Check current link speed
./ops/chklnkspeed.sh
./ops/linkchk.sh
```

#### 10.4 Device state management

```bash
./ops/resetpcidev.sh             # Reset PCI device (unbind/rebind)
./ops/resetdaemon.sh             # Reset container runtime daemon
./ops/grabmofed.sh               # Download MOFED driver packages
```

#### 10.5 InfiniBand-specific

```bash
./ops/setguids.sh                # Set GUIDs for InfiniBand devices
```

---

### Step 11: Node Management

#### 11.1 Node labeling

```bash
./ops/labelworker.sh             # Label worker nodes with default node selector
./ops/labelmaster.sh             # Label control plane nodes
./ops/labelsu.sh                 # Label nodes for scalable unit (SU) assignment
./ops/dellabelworker.sh          # Remove worker labels
./ops/annotatenode.sh <NODENAME> # Add annotations to nodes
```

#### 11.2 Taint management

```bash
./ops/gettaints.sh               # Display all node taints
./ops/rmtaints.sh                # Remove all NoSchedule taints
```

#### 11.3 Cordon/uncordon

```bash
# Cordon/uncordon are sourced as functions:
source ${NETOP_ROOT_DIR}/ops/cordon.sh
cordon                            # Cordon all worker nodes
uncordon                          # Uncordon all worker nodes
```

#### 11.4 Control plane as worker

```bash
# Make a control plane node schedulable
./ops/add-controlplane-as-worker.sh <NODENAME>

# Restore control plane taint
./ops/rm-controlplane-as-worker.sh <NODENAME>
```

#### 11.5 Cluster join

```bash
./ops/joincluster.sh             # Execute kubeadm join on worker nodes
./ops/reconnectworker.sh         # Reconnect disconnected workers
```

---

### Step 12: Diagnostics and Must-Gather

#### 12.1 Comprehensive must-gather

```bash
./must-gather-network.sh

# Python CLI alternative
python3 python_tools/netop_tools.py must-gather --output-dir /tmp/diagnostics
```

Collects all diagnostic data into `/tmp/nvidia-network-operator_YYYYMMDD_HHMM/`:

| Artifact | Contents |
|---|---|
| `must-gather.log` | Execution log |
| `network_operator_pod.*` | Operator pod status, YAML, and logs |
| `daemon_pod.*` | Daemon pod logs from all nodes |
| `network_crds.yaml` | Network CRD definitions |
| `ippool_crds.yaml` | IP pool configurations |
| `node_descriptions.yaml` | Node descriptions and labels |
| `pod_network_status.yaml` | Pod network attachment status |
| `openshift_version.yaml` | OpenShift cluster info (if applicable) |

Works on both Kubernetes and OpenShift clusters.

#### 12.2 Targeted diagnostics

```bash
./ops/getnetwork.sh              # Network attachment + NicClusterPolicy + RDMA + IP pools
./ops/checkipam.sh               # IPAM node annotations
./ops/checkippool.sh <NODENAME>  # IP pool usage on a node
./ops/checksriovstate.sh         # SR-IOV sync status
./ops/getNicClusterPolicy.sh     # NicClusterPolicy CRD YAML
./ops/getfinalizers.sh           # Object finalizers (cleanup debugging)
./ops/inspectetcd.sh             # Etcd cluster status and health
```

#### 12.3 Network testing

```bash
./ops/pingtest.sh                # Pod-to-pod connectivity test
./ops/check-iptables.sh          # Verify iptables rules
./ops/chkfw.sh                   # Check firewall status
```

---

### Step 13: Upgrade

#### 13.1 Upgrade Network Operator version

```bash
# Set new version in config
export NETOP_VERSION="26.1.0"

# Run upgrade
./upgrade/upgrade-network-operator.sh
```

The upgrade workflow:
1. Cordons all worker nodes
2. Scales Network Operator deployment to 0 replicas
3. Regenerates config for the new version (`mk-values.sh`, `mk-nic-cluster-policy.sh`, `mk-network-cr.sh`)
4. Applies updated NicClusterPolicy and CRDs
5. Applies updated network resources
6. Runs `helm upgrade` with new version
7. Uncordons worker nodes

#### 13.2 Supported versions

Available Helm chart versions: `24.7.0`, `24.10.0`, `24.10.1`, `25.1.0`, `25.4.0`, `25.7.0`, `25.10.0`, `26.1.0` (default)

---

### Step 14: Restart and Recovery

#### 14.1 Restart K8s components

```bash
./restart/restartk8master.sh     # Restart control plane (etcd, kubelet)
./restart/restartk8worker.sh     # Restart worker node (kubelet, containerd)
./restart/removek8master.sh      # Full master cleanup (kubeadm reset, remove all K8s dirs)
```

#### 14.2 Full cluster reset

```bash
./ops/reset-cluster.sh
```

This runs `kubeadm reset`, cleans up `/etc/cni`, `/var/lib/etcd`, `/etc/kubernetes`, flushes iptables, and reinitializes the cluster.

#### 14.3 Service management

```bash
./ops/stopdaemonset.sh           # Scale daemonsets to 0
./ops/netop-replicas.sh          # Manage network operator replicas
./ops/force_reboot.sh            # Force system reboot
./ops/shutdown.sh                # Graceful cluster shutdown
```

---

### Step 15: Cleanup and Uninstall

#### 15.1 Remove Network Operator

```bash
./uninstall/unins-network-operator.sh

# Python CLI alternative
python3 python_tools/netop_tools.py uninstall network-operator
```

Cleanup sequence:
1. Deletes SR-IOV, Mellanox, and node feature CRDs
2. Deletes network attachment definitions
3. Deletes NIC device and configuration CRDs
4. Deletes NicClusterPolicy resources
5. Removes Helm release
6. Force-deletes stuck namespace

#### 15.2 Component-specific cleanup

```bash
./uninstall/unins-calico.sh      # Remove Calico CNI
./uninstall/delcrds.sh           # Delete custom resource definitions
./uninstall/delipam.sh           # Remove IPAM resources and ConfigMaps
./uninstall/delsecret.sh         # Remove image pull secrets
./uninstall/delhelmchart.sh      # Uninstall Helm release
```

#### 15.3 Resource cleanup

```bash
./uninstall/delevictedpods.sh    # Remove stuck/evicted pods
./uninstall/delstucknamespace.sh # Force-delete terminating namespaces
./uninstall/netopcleanup.sh      # Comprehensive cleanup of all components
```

#### 15.4 Network-level cleanup

```bash
./ops/delete-network-cr.sh       # Delete all network CRDs (reverse order)
./ops/fluship.sh                 # Flush IP addresses
```

---

## Python CLI

The `python_tools/` directory provides a unified Python CLI as an alternative to the bash scripts. It requires only Python 3 (stdlib); PyYAML is optional for YAML output.

### Invocation

```bash
python3 python_tools/netop_tools.py [--verbose] [--config-file PATH] COMMAND
```

### Config management

```bash
python3 python_tools/netop_tools.py config show         # Display loaded config as JSON
python3 python_tools/netop_tools.py config validate      # Validate environment
python3 python_tools/netop_tools.py config export --format yaml --output config.yaml
```

### Implemented commands

| Command | Subcommands | Description |
|---|---|---|
| `install` | `helm`, `network-operator`, `chart`, `calico`, `crds`, `wait {k8s\|calico}` | Installation operations |
| `ops` | `network {status\|apply\|delete}`, `config values`, `node {label\|annotate\|cordon\|uncordon}`, `device {set-vfs\|get-vfs}`, `check {ipam\|sriov}` | Operational commands |
| `uninstall` | `network-operator`, `calico`, `evicted-pods`, `secret` | Cleanup operations |
| `must-gather` | `--output-dir DIR` | Collect diagnostics |
| `config` | `show`, `validate`, `export` | Configuration management |

### Legacy commands (backward compatible)

| Command | Description |
|---|---|
| `subnet <CIDR> <COUNT>` | Generate IPv4 subnet sequences |
| `setvfs <NUM> <BDF...>` | Configure SR-IOV VFs |
| `finddev` | Find device files in netop directories |
| `setuc [--usecase NAME]` | Setup use case symlink |
| `ins-k8 [--stage STAGE]` | Install K8s master (stages: master, init, calico, netop, all) |
| `start-k8` | Restart K8s master |

### Stub commands (not yet implemented)

`rdma`, `repo`, `restart`, `test`, `upgrade` — these exist as placeholders for future implementation.

---

## Container Registry Tools

### Harbor

Push and pull container images to/from a Harbor registry using different container runtimes:

```bash
# Login and push
./harbor/harborlogin.sh <image_name> [config_file]

# Docker runtime
./harbor/harbordockerpush.sh
./harbor/harbordockerpull.sh

# crictl (containerd)
./harbor/harborcrictlpush.sh
./harbor/harborcrictlpull.sh

# ctr (containerd native)
./harbor/harborctrpush.sh
./harbor/harborctrpull.sh
```

Configuration in `harbor/harbor.cfg`.

### NGC (NVIDIA GPU Cloud)

Manage images on the NGC registry:

```bash
# Login
./ngc/ngclogin.sh [api_key_file]

# NGC CLI operations
./ngc/ngcpullimage.sh
./ngc/ngcpushimage.sh
./ngc/ngc_exec.sh               # Execute commands in NGC environment
./ngc/ngcconfigset.sh           # Set NGC config parameters

# Docker operations against NGC
./ngc/dockerpull.sh
./ngc/dockerpushimage.sh
./ngc/dockertagimage.sh

# Remote Docker daemon
./ngc/env_DOCKER_HOST.sh        # Set up DOCKER_HOST for remote daemon
```

Configuration in `ngc/ngc.cfg`.

### Container image lifecycle

```bash
./ops/pull-release-containers.sh   # Pull all images for NETOP_VERSION
./ops/export-release-containers.sh # Export images for offline deployment
./ops/tag-release-containers.sh    # Tag images with release version
./ops/changeimageonly.sh           # Update image specs in deployments
./ops/pruneimages.sh               # Remove unused images
```

### Nerdctl

```bash
./nerdctl/nerdctl.sh             # Nerdctl wrapper
./nerdctl/nerdctlsav.sh          # Save images to archive
./nerdctl/nerdctlload.sh         # Load images from archive
```

---

## RDMA Debug Containers

Build specialized debug containers from `rdmatools/`:

| Dockerfile | Purpose |
|---|---|
| `Dockerfile.rdmadbg` | RDMA debugging environment |
| `Dockerfile.rdmadbg_cuda` | RDMA + CUDA debugging |
| `Dockerfile.rping` | RPing test utility |
| `Dockerfile.mft` | Mellanox Firmware Tools |
| `Dockerfile.nccldbg` | NCCL collective communications debugging |

```bash
# Build debug containers
./rdmatools/docker.build.sh

# Export/import for offline use
./rdmatools/ctrexport.sh
./rdmatools/ctrimportimage.sh

# Build NCCL from source
./rdmatools/bldnccl.sh

# Build rdma-core from source
./rdmatools/rdma-core.sh

# Install perftest with CUDA support
./rdmatools/install_perftest_cuda.sh
```

---

## ARP Tools

Utilities for static ARP configuration within test pods (`arptools/`):

```bash
# Set static ARP entry between pods
./arptools/setarp.sh <SERVER_POD> <CLIENT_POD> <NET_DEV1> [NET_DEV2] ...

# Show ARP table within pods
./arptools/getarps.sh

# Flush ARP cache
./arptools/flusharp.sh
```

---

## Testing Framework

Tests use YAML diff validation. Scripts generate config with `CREATE_CONFIG_ONLY=1` and compare against baseline YAML files.

### Run tests

```bash
source NETOP_ROOT_DIR.sh

# Run all tests
./tests/unitest.sh

# Run a specific test
./tests/unitest.sh tests/sriovnet_rdma/1/config
```

### Test structure

Each test directory under `tests/` contains:

| File | Purpose |
|---|---|
| `config` | Sourced as `GLOBAL_OPS_USER` (platform/version overrides) |
| `netop.cfg` | Optional use-case-specific overrides |
| `*.yaml` | Baseline YAML files compared against generated output |

### Available test scenarios

| Directory | Tests |
|---|---|
| `tests/sriovnet_rdma/` | `1/`, `2/`, `combined/`, `rdmaMode/` |
| `tests/sriovibnet_rdma/` | `basic/`, `combined/` |
| `tests/hostdev/` | `basic/`, `combined/` |
| `tests/macvlan_rdma_shared_device/` | `1/`, `combined/` |
| `tests/25_10/` | Version 25.10 compatibility (`sriovnet_rdma/1/`, `sriovibnet_rdma/1/`) |

### Adding a new test

1. Create a directory under `tests/` (e.g., `tests/my_test/`)
2. Add a `config` file with test-specific variable overrides
3. Run `CREATE_CONFIG_ONLY=1 GLOBAL_OPS_USER=tests/my_test/config ./install/ins-network-operator.sh`
4. Copy generated YAML from `usecase/${USECASE}/` to `tests/my_test/` as baselines
5. The test harness discovers tests by finding `config` files via `find`

CI runs `tests/unitest.sh` on ubuntu-22.04 on every push (`.github/workflows/main.yml`).

---

## Configuration Reference

### Cluster and Kubernetes

| Variable | Default | Description |
|---|---|---|
| `NETOP_ROOT_DIR` | (must set) | Repository root directory |
| `K8CIDR` | `192.168.0.0/16` | Kubernetes pod CIDR |
| `K8SVER` | `1.34` | Kubernetes version |
| `K8CL` | `kubectl` | CLI tool (`kubectl` or `oc`) |
| `HOST_OS` | `ubuntu` | Host OS (`ubuntu` or `rhel`) |
| `NETOP_NAMESPACE` | `nvidia-network-operator` | Operator namespace |
| `NETOP_APP_NAMESPACES` | `( "default" )` | Application pod namespaces |
| `NETOP_NODESELECTOR` | `node-role.kubernetes.io/worker` | Node selector for operator |

### Operator and Versions

| Variable | Default | Description |
|---|---|---|
| `NETOP_VERSION` | `26.1.0` | Network Operator Helm chart version |
| `PROD_VER` | `1` | `1`=production (NGC), `0`=staging |
| `CALICO_ROOT` | `3.28.2` | Calico CNI version |
| `CNI_PLUGINS_VERSION` | `v1.5.1` | CNI plugins version |
| `HELM_VERSION` | `3.15.4` | Helm version |
| `CRI_DOCKERD_VERSION` | `0.3.15` | Docker CRI version |

### Network

| Variable | Default | Description |
|---|---|---|
| `NETOP_NETWORK_RANGE` | `192.170.0.0/16` | Secondary RDMA network CIDR (L2, not routed) |
| `NETOP_NETWORK_START` | (empty) | Optional: start of IP pool range |
| `NETOP_NETWORK_END` | (empty) | Optional: end of IP pool range |
| `NETOP_NETWORK_GW` | (empty) | Gateway IP for RDMA network |
| `NETOP_NETWORK_ROUTE` | (empty) | Subnet route |
| `NETOP_NETWORK_EXCLUDE` | (empty) | Whereabouts excluded IP list |
| `NETOP_PERNODE_BLOCKSIZE` | `32` | IPs per node from IPAM pool |
| `NETOP_MTU` | `1500` | MTU (`9000` for RDMA) |
| `NETOP_VENDOR` | `15b3` | PCI vendor ID (Mellanox/NVIDIA) |

### Devices and Use Cases

| Variable | Default | Description |
|---|---|---|
| `USECASE` | `sriovnet_rdma` | Active use case |
| `NUM_VFS` | `8` (use-case-dependent) | SR-IOV virtual function count |
| `DEVICE_TYPES` | `( "connectx-6" )` | NIC types array |
| `NETOP_NETLIST` | (per platform) | Device list |
| `NETOP_SULIST` | `( "su-1" )` | Scalable unit list |

### IPAM

| Variable | Default | Description |
|---|---|---|
| `IPAM_TYPE` | `nv-ipam` | IPAM type (`nv-ipam`, `whereabouts`, `dhcp`) |
| `NVIPAM_POOL_TYPE` | `IPPool` | Pool type (`IPPool` or `CIDRPool`) |

### Output Control

| Variable | Default | Description |
|---|---|---|
| `CREATE_CONFIG_ONLY` | `1` | `1`=generate YAML only, `0`=deploy |
| `NETOP_BCM_CONFIG` | `false` | Combined multi-device YAML mode |
| `NETOP_COMBINED` | `false` | Combined YAML mode |
| `NETOP_TAG_VERSION` | `false` | Tag generated YAML with version |

### SR-IOV Node Pool

| Variable | Default | Description |
|---|---|---|
| `NETOP_SRIOV_NODE_POOL` | `1` | Max unavailable during updates (`1`, `"100%"`, or count) |

### Advanced

| Variable | Default | Description |
|---|---|---|
| `OFED_BLACKLIST_MODULES_FILE` | `/host/etc/modprobe.d/blacklist-ofed-modules.conf` | Path to OFED module blacklist file |
| `SYSCTL_CONFIG` | (empty) | Override ARP config inside test pods |
| `NCP_NODE_AFFINITY` | `false` | Enable NicClusterPolicy node affinity |
| `DOCA_TELEMETRY_SERVICE` | `false` | DOCA Telemetry Service |
| `ENTRYPOINT_DEBUG` | `false` | Debug container entrypoint |
| `DEBUG_LOG_FILE` | `/tmp/entrypoint_debug_cmds.log` | Debug log file |
| `DEBUG_SLEEP_SEC_ON_EXIT` | `300` | Debug sleep duration on exit |

---

## Platform Configs

Pre-built configurations in `config/`:

| Platform | Directory | Key Variants |
|---|---|---|
| **DGX** | `config/dgx/` | DGXB200 (BCM), DGXB300 (sriovnet/macvlan), DGXGB200 (ConnectX-7), DGXGB300 (ConnectX-8), DGXH100, DGXH200, DGXSpark |
| **Dell** | `config/dell/` | PowerEdge H100/H200 |
| **Lenovo** | `config/lenovo/` | ThinkSystem SR780a/SR675 (B200) |
| **SuperMicro** | `config/smc/` | A22GA-NBRT (B200, H200) |
| **OCI** | `config/oci/` | Oracle Cloud Infrastructure |
| **IGX** | `config/igx/` | NVIDIA IGX Orin RTX6000ADA |
| **KVM** | `config/kvm/` | DGXH100 in BCM hostSRIOV VM mode |
| **PDX** | `config/pdx/` | LENOVO H100 in BCM VM mode |
| **BCM11** | `config/bcm11/` | BCM test configurations |
| **Examples** | `config/examples/` | Standalone examples for each use case |

Key platform differences:

| Setting | Varies By |
|---|---|
| `DEVICE_TYPES` | NIC model per hardware (connectx-6, connectx-7, connectx-8) |
| `NETOP_NETLIST` | PCI addresses or interface names per system |
| `NUM_VFS` | 0, 4, 8, 12, or 16 depending on hardware/use case |
| `OFED_ENABLE` | `true` (container DOCA) vs `false` (kernel OFED) |
| `NIC_CONFIG_ENABLE` | `true` for platforms needing firmware tuning |
| `NETOP_BCM_CONFIG` | `true` for BCM/multi-device platforms |
| `MTU_DEFAULT` | `1500` (standard) vs `9000` (high-performance RDMA) |

---

## Directory Layout

| Directory | Purpose |
|---|---|
| `python_tools/` | Python CLI: unified command interface, config management, ops/install/uninstall commands |
| `ops/` | Core operations: config generation (`mk-*.sh`), CR management, device tools (~110 scripts) |
| `install/` | K8s cluster bootstrap, component installers, platform-specific (`ubuntu/`, `rhel/`), bug fixes (`fixes/`) |
| `uninstall/` | Cleanup and removal scripts |
| `upgrade/` | Network Operator version upgrade |
| `restart/` | K8s component restart and recovery |
| `config/` | Pre-built platform configurations |
| `usecase/` | Use case definitions with `netop.cfg` and generated YAML output |
| `tests/` | Test configs and baseline YAML files |
| `rdmatest/` | RDMA verification and bandwidth testing scripts |
| `rdmatools/` | RDMA debug containers, performance tools, Dockerfiles |
| `harbor/` | Harbor container registry push/pull tools |
| `ngc/` | NGC (NVIDIA GPU Cloud) registry management |
| `arptools/` | ARP configuration utilities |
| `repotools/` | Git repository workflow automation |
| `containers/` | Container image lists per operator version (CSV format) |
| `nerdctl/` | Nerdctl (containerd CLI) wrapper scripts |
| `release/` | Versioned Helm chart configurations |
