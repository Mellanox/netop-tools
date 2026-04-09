---
name: deploying-network-operator
description: Deploy NVIDIA Network Operator to a Kubernetes cluster via netop-tools. Use when installing network operator, setting up RDMA networking, deploying SR-IOV, running ins-network-operator.sh, generating Helm values, applying network CRDs, or troubleshooting deployment failures.
---

# Deploying Network Operator

Guide the full deployment pipeline from config generation through Helm install and CRD application.

## Prerequisites

```bash
source NETOP_ROOT_DIR.sh
# global_ops_user.cfg must exist and be edited for the target platform
source global_ops.cfg
```

## Deployment Pipeline

```bash
# 1. Set use case
./setuc.sh ${USECASE}

# 2. Generate all config (dry run by default: CREATE_CONFIG_ONLY=1)
cd usecase/${USECASE}
${NETOP_ROOT_DIR}/ops/mk-config.sh

# 3. Review generated YAML before deploying
ls -la *.yaml

# 4. Deploy (set CREATE_CONFIG_ONLY=0 to actually run helm/kubectl)
export CREATE_CONFIG_ONLY=0
${NETOP_ROOT_DIR}/install/ins-network-operator.sh
```

### What mk-config.sh generates

| Script | Output | Purpose |
|---|---|---|
| `ops/mk-values.sh` | `values.yaml` | Helm values (feature flags, images) |
| `ops/mk-nic-cluster-policy.sh` | `NicClusterPolicy.yaml` | NicClusterPolicy CRD |
| `ops/mk-network-cr.sh` | `network.yaml` + `ippool-*.yaml` | Network + IPAM CRDs per device |
| `ops/mk-sriov-node-pool.sh` | `sriov-node-pool-config.yaml` | SR-IOV VF allocation |
| `ops/mk-nic-config.sh` | `nic-config-crd-{type}.yaml` | NIC firmware config (if `NIC_CONFIG_ENABLE=true`) |

### Python CLI alternative

```bash
python3 python_tools/netop_tools.py install helm
python3 python_tools/netop_tools.py install chart
python3 python_tools/netop_tools.py install network-operator
python3 python_tools/netop_tools.py install calico
python3 python_tools/netop_tools.py install crds
```

## Post-Deploy Verification

```bash
kubectl get pods -n ${NETOP_NAMESPACE}
./ops/getnetwork.sh
./ops/checksriovstate.sh
./ops/syncsriov.sh              # Wait for SR-IOV sync (can take 10+ min)
./ops/checkipam.sh
```

## Common Failures

| Symptom | Cause | Fix |
|---|---|---|
| "User configuration file not found" | Missing `global_ops_user.cfg` | Copy from `config/{platform}/` |
| Helm chart not found | Wrong `NETOP_VERSION` | Check available versions: 24.7.0 through 26.1.0 |
| No VFs created | `CREATE_CONFIG_ONLY=1` (default) | Set `CREATE_CONFIG_ONLY=0` before deploy |
| SR-IOV sync stuck | Normal — can take 10 min | Run `./ops/syncsriov.sh` to wait |
| Pod network not attached | Wrong namespace | Ensure pod and network CRD are in same namespace |
| IP pool exhausted | `NETOP_PERNODE_BLOCKSIZE` too small | Increase blocksize or `NETOP_NETWORK_RANGE` |

## Key Config Variables

- `CREATE_CONFIG_ONLY` — `1` (dry run) or `0` (deploy). **Default is 1.**
- `NETOP_VERSION` — Helm chart version (default `26.1.0`)
- `USECASE` — Use case name (default `sriovnet_rdma`)
- `NETOP_NETLIST` — Device list (critical, format varies by use case)
- `IPAM_TYPE` — `nv-ipam` (large clusters) or `whereabouts` (<60 nodes)
