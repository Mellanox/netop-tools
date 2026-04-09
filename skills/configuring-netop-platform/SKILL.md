---
name: configuring-netop-platform
description: Configure netop-tools for a specific hardware platform and use case. Use when setting up global_ops_user.cfg, choosing a use case (sriovnet_rdma, sriovibnet_rdma, hostdev, ipoib, macvlan), selecting IPAM type, configuring NETOP_NETLIST device list, setting feature flags, or switching between platforms (DGX, Dell, Lenovo, OCI, SuperMicro).
---

# Configuring netop-tools Platform

Set up configuration for your hardware platform and networking use case.

## Configuration Cascade

**Priority** (highest to lowest): ENV vars > `global_ops_user.cfg` > `usecase/{USECASE}/netop.cfg` > `global_ops.cfg` defaults

## Step 1: Copy Platform Config

```bash
source NETOP_ROOT_DIR.sh

# Available platforms:
ls config/
# bcm11  dell  dgx  examples  igx  kvm  lenovo  oci  pdx  smc

# Copy for your hardware:
cp config/dgx/global_ops_user.cfg.DGXGB300.bcm global_ops_user.cfg
# Edit global_ops_user.cfg
```

### Platform Quick Reference

| Platform | Key Config | NIC | Typical Use Case |
|---|---|---|---|
| DGX B200/B300 | `config/dgx/*.bcm` | ConnectX-7/8 | `sriovibnet_rdma` or `sriovnet_rdma` |
| DGX GB200 | `config/dgx/*.DGXGB200.bcm` | ConnectX-7, 16 VFs | `sriovibnet_rdma` |
| DGX GB300 | `config/dgx/*.DGXGB300.bcm` | ConnectX-8, 16 VFs | `sriovibnet_rdma` |
| DGX H100/H200 | `config/dgx/*.bcm` | ConnectX-7 | `sriovnet_rdma` |
| Dell PowerEdge | `config/dell/*` | ConnectX-7 | `sriovnet_rdma` |
| OCI | `config/oci/*` | ConnectX, 16 VFs | `sriovnet_rdma` |
| Examples | `config/examples/*` | Generic | One per use case |

## Step 2: Choose Use Case

| Use Case | Network Type | VFs | Device Format | When to Use |
|---|---|---|---|---|
| `sriovnet_rdma` | SR-IOV Ethernet | 8 | PCI BDF: `0000:08:00.0` | Most common, RoCE networks |
| `sriovibnet_rdma` | SR-IOV InfiniBand | 8 | IB interface: `ibs0f1` | InfiniBand fabrics |
| `hostdev_rdma_sriov` | HostDevice | 8 | Multi-PCI: `0000:07:00.0,0000:08:00.0` | Exclusive device access |
| `ipoib_rdma_shared_device` | IPoIB shared | 0 | IB: `ibs0f0` (field3=HCAMAX) | Shared IB, no VFs |
| `macvlan_rdma_shared_device` | Macvlan shared | 0 | Eth: `ens2f0np0` (field3=HCAMAX) | Shared Ethernet, no VFs |

## Step 3: Configure NETOP_NETLIST

**This is the most error-prone setting.** Format: `( index,,,device_id )`

```bash
# SR-IOV Ethernet — PCI BDF addresses
NETOP_NETLIST=( a,,,0000:08:00.0 b,,,0000:86:00.1 )

# SR-IOV InfiniBand — IB interface names
NETOP_NETLIST=( a,,,ibs0f1 b,,,ibs1f1 )

# HostDevice — multiple PCI per entry
NETOP_NETLIST=( a,,,0000:07:00.0,0000:08:00.0 )

# Shared device (field3 = HCAMAX, typically 63)
NETOP_NETLIST=( a,,63,ibs0f0 b,,63,ibs0f1 )
```

**Common mistakes**: Using PCI BDF for IB use cases, missing commas, wrong field count.

## Step 4: Set Feature Flags

| Variable | Default | Set When |
|---|---|---|
| `OFED_ENABLE` | `true` | `false` if using kernel OFED (not container) |
| `NFD_ENABLE` | `true` | `false` if GPU-operator runs NFD |
| `NIC_CONFIG_ENABLE` | `false` | `true` for firmware tuning (GB300, etc.) |
| `IPAM_TYPE` | `nv-ipam` | `whereabouts` for <60 nodes, `dhcp` for external DHCP |
| `NETOP_BCM_CONFIG` | `false` | `true` for multi-device combined YAML (DGX) |
| `CREATE_CONFIG_ONLY` | `1` | `0` to actually deploy |

## Step 5: Validate

```bash
source global_ops.cfg
# Generate config without deploying:
./install/ins-network-operator.sh
# Review generated YAML:
ls -la usecase/${USECASE}/*.yaml

# Python CLI validation:
python3 python_tools/netop_tools.py config validate
python3 python_tools/netop_tools.py config show
```
