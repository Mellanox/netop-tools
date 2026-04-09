---
name: upgrading-network-operator
description: Upgrade NVIDIA Network Operator to a new version. Use when changing NETOP_VERSION, running upgrade-network-operator.sh, migrating between operator versions, handling CRD schema changes, or rolling back a failed upgrade.
---

# Upgrading Network Operator

Upgrade the Network Operator Helm release to a new version with zero-downtime node rolling.

## Supported Versions

`24.7.0`, `24.10.0`, `24.10.1`, `25.1.0`, `25.4.0`, `25.7.0`, `25.10.0`, `26.1.0` (default)

## Pre-Upgrade Checklist

1. Verify target version exists: `helm search repo nvidia/network-operator --versions`
2. Check K8s compatibility (26.1.0 requires K8s 1.32+)
3. Generate config for new version with `CREATE_CONFIG_ONLY=1` first
4. Review YAML diffs between old and new generated configs
5. Ensure all nodes are healthy: `kubectl get nodes`

## Upgrade Procedure

```bash
# 1. Set new version
export NETOP_VERSION="26.1.0"
source global_ops.cfg

# 2. Preview config changes (dry run)
export CREATE_CONFIG_ONLY=1
cd usecase/${USECASE}
${NETOP_ROOT_DIR}/ops/mk-config.sh
# Review generated YAML

# 3. Run upgrade
export CREATE_CONFIG_ONLY=0
${NETOP_ROOT_DIR}/upgrade/upgrade-network-operator.sh
```

### What the upgrade script does

1. Cordons all worker nodes
2. Scales Network Operator deployment to 0 replicas
3. Regenerates config: `mk-values.sh`, `mk-nic-cluster-policy.sh`, `mk-network-cr.sh`
4. Applies updated NicClusterPolicy
5. Applies new CRDs via `applycrds.sh`
6. Applies network resources via `apply-network-cr.sh`
7. Updates NIC config (if `NIC_CONFIG_ENABLE=true`)
8. Runs `helm upgrade`
9. Uncordons worker nodes

## Post-Upgrade Verification

```bash
kubectl get pods -n ${NETOP_NAMESPACE}
./ops/getnetwork.sh
./ops/checksriovstate.sh
./ops/syncsriov.sh
./ops/checkipam.sh
```

## Version-Specific Notes

| Version | Key Changes |
|---|---|
| 25.10.* | `MAINTENANCE_OPERATOR_ENABLE` defaults to `NIC_CONFIG_ENABLE` value |
| 26.1.* | `MAINTENANCE_OPERATOR_ENABLE` defaults to `true` independently |
| 25.1.0 | Uses `nicConfigurationOperator` parameter (older API) |
| 25.4.0+ | Uses `deployNodeFeatureRules` for NFD |

## Rollback

If upgrade fails, restore previous config and re-run:

```bash
export NETOP_VERSION="<previous_version>"
source global_ops.cfg
${NETOP_ROOT_DIR}/upgrade/upgrade-network-operator.sh
```

## Common Failures

| Symptom | Fix |
|---|---|
| Helm chart not found | Verify `NETOP_VERSION` and `helm repo update` |
| CRD validation errors | Check feature gate compatibility with new version |
| Nodes stuck cordoned | Run `source ops/cordon.sh && uncordon` |
| Finalizers blocking delete | `./ops/getfinalizers.sh`, then patch to remove |
