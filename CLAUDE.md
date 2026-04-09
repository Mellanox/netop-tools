# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**netop-tools** automates deployment and management of NVIDIA Network Operator in Kubernetes clusters. It handles RDMA networking, SR-IOV Virtual Functions (VFs), IPoIB, Macvlan, and HostDev network configurations for AI/ML workloads on bare metal and virtualized Kubernetes environments.

The codebase consists of ~250 Bash scripts organized by function, plus a Python CLI (`python_tools/`) that provides a unified interface for common operations.

## Setup

```bash
# Bash workflow
source NETOP_ROOT_DIR.sh                    # exports NETOP_ROOT_DIR=$(pwd)
cp config/{platform}/global_ops_user.cfg.{variant} global_ops_user.cfg
# edit global_ops_user.cfg for your environment
source global_ops.cfg                       # loads all config (requires global_ops_user.cfg)
./setuc.sh [usecase]                        # creates uc/ symlink → usecase/{USECASE}/

# Python CLI (alternative)
python3 python_tools/netop_tools.py config show       # view loaded config
python3 python_tools/netop_tools.py config validate   # validate environment
```

## Testing

Tests use YAML diff validation — scripts generate config with `CREATE_CONFIG_ONLY=1` and compare against baseline YAML files in `tests/{usecase}/`.

```bash
# Run all tests (requires NETOP_ROOT_DIR to be set)
source NETOP_ROOT_DIR.sh
./tests/unitest.sh

# Run a single test by passing its config file path
./tests/unitest.sh tests/sriovnet_rdma/config
```

CI (`.github/workflows/main.yml`) runs `tests/unitest.sh` on ubuntu-22.04 on every push.

**Adding tests**: Create a directory under `tests/` with a `config` file (sourced as `GLOBAL_OPS_USER`), optional `netop.cfg` overrides, and `*.yaml` baseline files. The test harness discovers test directories by finding `config` files via `find`.

## Architecture

### Configuration Cascade

**Priority**: ENV vars > `global_ops_user.cfg` > `usecase/{USECASE}/netop.cfg` > defaults in `global_ops.cfg`

- `global_ops.cfg` — master config (~250 lines). Sources `global_ops_user.cfg` first, then `usecase/${USECASE}/netop.cfg` at the end. Exports 40+ variables controlling K8s version, operator version, IPAM, VF counts, feature gates, etc.
- `global_ops_user.cfg` — platform/user overrides (not committed). Copy from `config/{platform}/` variants.
- `usecase/{usecase}/netop.cfg` — use-case-specific overrides (device lists, network files, etc.)

`NETOP_ROOT_DIR` must be set before sourcing any config. The `CREATE_CONFIG_ONLY` variable (default `"1"`) controls whether scripts actually execute `helm`/`kubectl` commands or just echo them — this is how the test harness works.

### Python CLI (`python_tools/`)

Unified Python CLI replacing common bash workflows. Invocation: `python3 python_tools/netop_tools.py [--verbose] [--config-file PATH] COMMAND`

- `netop_tools.py` — main entry point, argparse setup, command dispatch
- `config.py` — `NetOpConfig` dataclass, 5-stage config cascade (defaults → auto-detect → global_ops.cfg → ENV → global_ops_user.cfg), shell config parser
- `utils.py` — `CommandResult` dataclass, `run_command()`, kubectl/helm/docker wrappers, validation helpers
- `k8s_tools.py` — K8s operations (setup_usecase, install_k8s_master, cluster_status)
- `must_gather.py` — `NetworkOperatorMustGather` class, artifact collection into timestamped directory

**Implemented commands** (`commands/`):
- `ops_commands.py` — `ops network {status|apply|delete}`, `ops config values`, `ops node {label|annotate|cordon|uncordon}`, `ops device {set-vfs|get-vfs}`, `ops check {ipam|sriov}`
- `install_commands.py` — `install {helm|network-operator|chart|calico|crds}`, `install wait {k8s|calico}`
- `uninstall_commands.py` — `uninstall {network-operator|calico|evicted-pods|secret}`

**Legacy commands** (backward-compatible): `subnet`, `setvfs`, `finddev`, `setuc`, `ins-k8`, `start-k8`, `must-gather`, `config {show|validate|export}`

**Stub commands** (not yet implemented): `rdma`, `repo`, `restart`, `test`, `upgrade`

Dependencies: Python 3 (stdlib only), optional PyYAML for YAML output.

### Deployment Pipeline

```
ins-network-operator.sh
  ├─ setuc.sh                    → validate + create uc/ symlink
  ├─ mksecret.sh                 → image pull secret
  ├─ ops/mk-config.sh            → orchestrates all config generation:
  │   ├─ ops/mk-values.sh        → Helm values.yaml (feature flags, images)
  │   ├─ ops/mk-nic-cluster-policy.sh → NicClusterPolicy CRD
  │   ├─ ops/mk-network-cr.sh    → SriovNetwork + NetworkAttachmentDefinition
  │   ├─ ops/mk-ipam-cr.sh       → IPPool or CIDRPool
  │   ├─ ops/mk-sriov-node-pool.sh → SR-IOV VF allocation policy
  │   └─ ops/mk-nic-config.sh    → NIC firmware config (if NIC_CONFIG_ENABLE=true)
  ├─ helm install network-operator
  └─ ops/apply-network-cr.sh     → kubectl apply all generated CRDs
```

### Key Conventions

- **Use-case symlink**: `./setuc.sh` creates `uc/` → `usecase/${USECASE}/`. Scripts reference `${USECASE_DIR}` or `./uc/` interchangeably. Generated YAML files land in the use-case directory.
- **Device list format**: `NETOP_NETLIST=( a,,,0000:08:00.0 b,,,0000:86:00.1 )` — tuple of `device_index,reserved,reserved,pci_bdf`. Separate IPPool/SriovNetwork CRDs are generated per device.
- **Combined mode**: When `NETOP_BCM_CONFIG=true`, multiple network definitions are merged into single `combined-*.yaml` files instead of separate per-device files.
- **Subnet generation**: `ops/generate_subnets.sh` splits `NETOP_NETWORK_RANGE` into per-node blocks of `NETOP_PERNODE_BLOCKSIZE` (default 32) IPs.

### Directory Layout

| Directory | Purpose |
|---|---|
| `ops/` | Core operations: config generation (`mk-*.sh`), CR management, device tools (~110 scripts) |
| `install/` | K8s cluster bootstrap, platform-specific installers (`ubuntu/`, `rhel/`) |
| `uninstall/` | Cleanup/removal scripts |
| `python_tools/` | Python CLI: unified command interface, config management, ops/install/uninstall commands |
| `config/{platform}/` | Pre-built platform configs: bcm11, dell, dgx (B200/B300/GB200/GB300/H100/H200/Spark), examples, igx, kvm, lenovo, oci, pdx, smc |
| `usecase/{name}/` | Use-case definitions with `netop.cfg` and generated YAML output |
| `tests/` | Test configs + baseline YAML files |
| `release/` | Versioned Helm chart configurations (controlled by `NETOP_VERSION`, default `26.1.0`) |

### Use Cases

| Use Case | Description | VFs |
|---|---|---|
| `sriovnet_rdma` | SR-IOV with RDMA (default) | 8 |
| `sriovibnet_rdma` | SR-IOV InfiniBand with RDMA | 8 |
| `hostdev_rdma_sriov` | HostDevice with SR-IOV | 8 |
| `ipoib_rdma_shared_device` | IPoIB with shared device | 0 |
| `macvlan_rdma_shared_device` | Macvlan with shared RDMA | 0 |

### Key Configuration Variables

- `NETOP_VERSION` — Helm chart version (default `26.1.0`)
- `NETOP_NAMESPACE` — operator namespace (default `nvidia-network-operator`)
- `NETOP_NETWORK_RANGE` — secondary RDMA network CIDR (L2, not routed)
- `NETOP_NETLIST` — array of PCI devices to configure
- `USECASE` — active use case (default `sriovnet_rdma`)
- `NUM_VFS` — SR-IOV virtual function count
- `IPAM_TYPE` — IP management (`nv-ipam` for large clusters, `whereabouts` for <60 nodes)
- `DEVICE_TYPES` — NIC types array (e.g., `connectx-6`, `connectx-7`)
- `CREATE_CONFIG_ONLY` — `"1"` to generate YAML only without deploying
- `NETOP_BCM_CONFIG` — `"true"` enables combined multi-device YAML mode
- `OFED_BLACKLIST_MODULES_FILE` — path to OFED blacklist file (default `/host/etc/modprobe.d/blacklist-ofed-modules.conf`)
