# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**netop-tools** automates deployment and management of NVIDIA Network Operator in Kubernetes clusters. It handles RDMA networking, SR-IOV Virtual Functions (VFs), IPoIB, Macvlan, and HostDev network configurations for AI/ML workloads on bare metal and virtualized Kubernetes environments.

The tooling is undergoing a migration from Bash scripts (legacy, 228+ scripts) to a unified Python CLI (`python_tools/`).

## Setup

```bash
# Set the required environment variable
source NETOP_ROOT_DIR.sh

# Copy and customize platform config
cp config/{platform}/global_ops_user.cfg global_ops_user.cfg
# Edit global_ops_user.cfg for your environment

# Load full configuration
source global_ops.cfg
```

## Testing

```bash
# Unit tests only (safe, no infrastructure required)
./run_tests.sh unit

# Test a specific command
./run_tests.sh command subnet

# Quick validation
./run_tests.sh quick

# Full integration tests (requires K8s cluster + hardware)
./run_tests.sh integration

# Direct Python test file
python3 test_netop_tools.py
```

GitHub Actions (`.github/workflows/main.yml`) runs tests on every push against ubuntu-22.04.

## Architecture

### Configuration System

The configuration system is the foundation of the entire toolset:

- `global_ops.cfg` — master config with 250+ variables (K8s, network, hardware, operator versions). Sources `global_ops_user.cfg` and use-case-specific `netop.cfg`.
- `global_ops_user.cfg` — user/platform overrides (not committed per platform)
- `config/{platform}/global_ops_user.cfg.*` — pre-built platform configs (dgx, dell, lenovo, oci, pdx, smc)
- `usecase/{usecase}/netop.cfg` — use-case-specific overrides

**Priority**: ENV vars > user config > use-case config > defaults in `global_ops.cfg`

`NETOP_ROOT_DIR` must be set before sourcing any config.

### Python Tools (`python_tools/`)

Unified CLI replacing the legacy bash scripts:

- `netop_tools.py` — main entry point, argparse setup, command dispatch
- `config.py` — `NetOpConfig` dataclass + config loading from shell-sourced variables
- `utils.py` — shared subprocess helpers, logging
- `subnet_generator.py` — IP subnet generation for IPAM
- `device_tools.py` — SR-IOV VF configuration, PCI device management
- `k8s_tools.py` — kubectl/helm operations, K8s resource management
- `must_gather.py` — diagnostic collection from K8s cluster
- `commands/` — hierarchical command implementations (ops, install, uninstall, arp, harbor, etc.)

### Legacy Bash Scripts

Organized by function:
- `ops/` — network operations, resource generation (mk-network-cr.sh, mk-values.sh, apply-network-cr.sh)
- `install/` — K8s and component installation
- `uninstall/` — cleanup scripts
- `arptools/`, `rdmatest/`, `harbor/`, `repotools/` — specialized tools

### Use Cases

Each use case directory (`usecase/{name}/`) contains network definitions, IP pool configs, and app templates:

| Use Case | Description |
|---|---|
| `sriovnet_rdma` | SR-IOV with RDMA (most common) |
| `sriovibnet_rdma` | SR-IOV InfiniBand with RDMA |
| `hostdev_rdma_sriov` | HostDevice with SR-IOV |
| `ipoib_rdma_shared_device` | IPoIB with shared device |
| `macvlan_rdma_shared_device` | Macvlan with shared RDMA |

### Network CR Generation Workflow

```
global_ops.cfg + global_ops_user.cfg
    ↓
ops/mk-network-cr.sh
    ├─ mk-nic-cluster-policy.sh  → NicClusterPolicy CRD
    ├─ mk-sriovnet-node-policy.sh → SriovNetworkNodePolicy
    ├─ mk-network-attachment.sh  → NetworkAttachmentDefinition
    └─ mk-ipam-cr.sh             → IPPool or CIDRPool
    ↓
ops/mk-values.sh → Helm values (operator feature flags, image versions)
    ↓
helm install network-operator + kubectl apply CRDs
```

### Helm Charts

`release/` contains versioned Helm chart configurations from 24.10.0 through 26.1.0. The active version is controlled by `NETOP_VERSION` in config.

### Key Configuration Variables

- `NETOP_VERSION` — Network Operator helm chart version
- `NETOP_NAMESPACE` / `NETOP_NETWORK_RANGE` — deployment namespace and CIDR
- `NETOP_VENDOR` — PCI vendor ID (default `"15b3"` for Mellanox/NVIDIA)
- `NUM_VFS` — number of SR-IOV virtual functions
- `IPAM_TYPE` / `NVIPAM_POOL_TYPE` — IP address management configuration
- `NFD_ENABLE` / `NIC_CONFIG_ENABLE` / `MAINTENANCE_OPERATOR_ENABLE` — operator feature flags
- `K8CL` — Kubernetes cluster name / `K8SVER` — K8s version
- `USECASE` — active use case (e.g., `sriovnet_rdma`)

## Bash-to-Python Migration

See `BASH_TO_PYTHON_CONVERSION.md` for mapping between legacy bash commands and their Python equivalents. When adding new functionality, prefer Python in `python_tools/commands/` and maintain backward-compatible command names.
