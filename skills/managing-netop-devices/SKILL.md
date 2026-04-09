---
name: managing-netop-devices
description: Manage SR-IOV virtual functions, PCI devices, link speed, and RDMA testing for NVIDIA Network Operator. Use when setting VFs, querying PCI devices, forcing link speed, running RDMA bandwidth tests, checking RDMA capability, managing node labels and taints, or cordoning nodes.
---

# Managing Network Devices and Nodes

Device management, RDMA testing, and node operations for Network Operator clusters.

## SR-IOV Virtual Functions

```bash
# Set VFs on PCI devices (run on worker node)
./setvfs.sh <NUM_VFS> <BDF1> [BDF2] ...
./setvfs.sh 8 0000:08:00.0 0000:86:00.1

# Query current VF count
./ops/getnumvfs.sh

# Python CLI
python3 python_tools/netop_tools.py ops device set-vfs 8
python3 python_tools/netop_tools.py ops device get-vfs
```

## PCI Device Info

```bash
./ops/getpci.sh                  # List PCI devices
./ops/getpciid.sh                # Vendor IDs (15b3 = NVIDIA/Mellanox)
./ops/grabpci.sh                 # PCI config details
./ops/devlist.sh                 # Network devices
```

## Link Speed

```bash
# Force link speed (disables auto-negotiation)
./ops/force_link_speed.sh <DEV> <SPEED> <XVAL>
# Speeds: 10G, 25G, 40G, 50G, 100G, 200G, 400G, 800G
# XVAL: 1X, 2X, 4X, 8X (must match speed)
./ops/force_link_speed.sh mlx5_0 400G 4X

# Check current speed
./ops/chklnkspeed.sh
./ops/linkchk.sh
```

## RDMA Testing

```bash
# Verify RDMA capability
./rdmatest/check_rdma.sh
./rdmatest/get_rdma_dev.sh

# Disable PCI ACS for peer-to-peer (bare metal only)
./rdmatest/disable_acs.sh

# RoCE bandwidth test (server → client)
./rdmatest/rocesrv.sh             # On server pod
./rdmatest/roceclnt.sh            # On client pod

# InfiniBand bandwidth test
./rdmatest/rdmasrv.sh             # Server: ib_send_bw
./rdmatest/rdmaclnt.sh            # Client

# GPU Direct RDMA
./rdmatest/gdrsrv.sh              # Server
./rdmatest/gdrclt.sh              # Client

# Performance testing with CUDA
./rdmatools/perftestcuda.sh
```

## Node Management

```bash
# Labeling
./ops/labelworker.sh              # Label workers
./ops/labelmaster.sh              # Label control plane
./ops/labelsu.sh                  # Label for scalable units
./ops/dellabelworker.sh           # Remove worker labels

# Taints
./ops/gettaints.sh                # Show taints
./ops/rmtaints.sh                 # Remove NoSchedule taints

# Cordon (sourced as functions)
source ${NETOP_ROOT_DIR}/ops/cordon.sh
cordon                             # Cordon all workers
uncordon                           # Uncordon all workers

# Python CLI
python3 python_tools/netop_tools.py ops node cordon
python3 python_tools/netop_tools.py ops node uncordon
python3 python_tools/netop_tools.py ops node label rdma-capable true

# Control plane as worker
./ops/add-controlplane-as-worker.sh <NODENAME>
./ops/rm-controlplane-as-worker.sh <NODENAME>
```

## Application Pods

```bash
# Create test pod YAML
${NETOP_ROOT_DIR}/ops/mk-app.sh <name> [num_pods] [namespace] [worker_node]
${NETOP_ROOT_DIR}/ops/mk-app.sh test 2 default worker-01

# Deploy
${NETOP_ROOT_DIR}/ops/run-app.sh test
```
