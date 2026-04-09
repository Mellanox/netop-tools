---
name: troubleshooting-network-operator
description: Diagnose and fix NVIDIA Network Operator issues in Kubernetes. Use when pods can't get RDMA network, SR-IOV VFs not showing, IP allocation failures, network attachment missing, must-gather diagnostics, operator pods crashing, NicClusterPolicy errors, or IPAM pool exhaustion.
---

# Troubleshooting Network Operator

Systematic diagnostic flow for Network Operator issues.

## Step 1: Collect Diagnostics

```bash
# Full must-gather (saves to /tmp/nvidia-network-operator_YYYYMMDD_HHMM/)
./must-gather-network.sh

# Python CLI alternative
python3 python_tools/netop_tools.py must-gather --output-dir /tmp/diag
```

## Step 2: Check Operator Health

```bash
kubectl get pods -n ${NETOP_NAMESPACE}
./ops/getNicClusterPolicy.sh
./ops/getnetwork.sh
```

**What to look for**: All operator/daemon pods should be `Running`. NicClusterPolicy should show `state: ready`.

## Step 3: Targeted Checks

### Network not attaching to pods

```bash
./ops/get-network-attach-defs.sh   # Verify NetworkAttachmentDefinitions exist
./ops/getnetworkstatus.sh          # Check pod network-status annotations
./ops/getpodnetworkstatus.sh       # Pod-level details
```

### SR-IOV VFs not available

```bash
./ops/checksriovstate.sh           # Check sync status
./ops/syncsriov.sh                 # Wait for sync (up to 10 min)
./ops/getsriovnodepolicy.sh        # Verify node policies
./ops/getsriovnodestate.sh         # Per-node SR-IOV state
./ops/getnumvfs.sh                 # Query actual VF count on devices
```

### IP allocation failures

```bash
./ops/checkipam.sh                 # Node IPAM annotations
./ops/checkippool.sh <NODENAME>    # Per-node IP usage
./ops/getippool.sh                 # Pool definitions
./ops/getallocatedip.sh            # Currently allocated IPs
# Python CLI
python3 python_tools/netop_tools.py ops check ipam
```

### Connectivity issues

```bash
./ops/pingtest.sh                  # Pod-to-pod connectivity
./ops/check-iptables.sh            # Firewall rules
./ops/chkfw.sh                     # Firewall status
```

## Diagnostic Decision Tree

| Symptom | Check | Likely Cause |
|---|---|---|
| Operator pod CrashLoopBackOff | `kubectl logs -n ${NETOP_NAMESPACE} <pod>` | Version mismatch, missing CRDs |
| No VFs on node | `checksriovstate.sh` | Sync in progress, wrong PCI BDF in `NETOP_NETLIST` |
| Pod stuck Pending | `kubectl describe pod <pod>` | Resource not available (wrong resource name) |
| IP not allocated | `checkipam.sh` | Pool exhausted, wrong `IPAM_TYPE`, pool not applied |
| Network annotation missing | `getnetworkstatus.sh` | NetworkAttachmentDefinition not in pod namespace |
| Finalizer blocking delete | `getfinalizers.sh` | Orphaned finalizer — patch to remove |
| MTU errors | Check `NETOP_MTU` in config | Mismatch between config and physical network |

## Cleanup Stuck Resources

```bash
./ops/getfinalizers.sh             # Find stuck finalizers
./uninstall/delstucknamespace.sh   # Force-delete terminating namespaces
./uninstall/delevictedpods.sh      # Remove evicted pods
```

## Key Log Locations in Must-Gather

| File | Contents |
|---|---|
| `network_operator_pod.log` | Operator controller logs |
| `network_operand_pod_*.log` | Per-daemon logs (OFED, device plugin, IPAM) |
| `custom_resource_*.yaml` | All CRD state snapshots |
| `nodes.yaml` | Node labels, taints, allocatable resources |
