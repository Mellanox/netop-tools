#!/bin/bash
#
# Generate SR-IOV Network Node Policy for InfiniBand devices  
# https://github.com/k8snetworkplumbingwg/sriov-network-operator/tree/master
#
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "ERROR: Missing required parameters"
  echo "Usage: $0 {NETWORK_NAME} {NETWORK_NIDX} {DEVICE_LST}"
  echo "Examples:"
  echo "  Single device:    $0 sriovibnet-rdma-default-a-su-1-cr a 0000:24:00.0"
  echo "  Multiple devices: $0 sriovibnet-rdma-default-a-su-1-cr a 0000:24:00.0,0000:25:00.0"
  echo "  Interface names:  $0 sriovibnet-rdma-default-a-su-1-cr a ib0,ib1"
  exit 1
fi

# Validate environment
if [ -z "${NETOP_ROOT_DIR:-}" ]; then
    echo "ERROR: NETOP_ROOT_DIR is not set"
    exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
NETWORK_NAME="${1}"
shift
NIDX="${1}"
shift
DEVICE_LST="${1}"
shift

# Validate parameters
if [ -z "${NETWORK_NAME}" ]; then
    echo "ERROR: NETWORK_NAME cannot be empty"
    exit 1
fi

if [ -z "${NIDX}" ]; then
    echo "ERROR: NETWORK_NIDX cannot be empty"
    exit 1
fi

if [ -z "${DEVICE_LST}" ]; then
    echo "ERROR: DEVICE_LST cannot be empty"
    exit 1
fi

# Debug output (to stderr so it doesn't interfere with YAML output)
echo "Generating SR-IOV InfiniBand node policy for:" >&2
echo "  Network: ${NETWORK_NAME}" >&2
echo "  Index: ${NIDX}" >&2
echo "  Devices: ${DEVICE_LST}" >&2

# Handle multiple devices - convert comma-separated list to YAML array format
if [[ "${DEVICE_LST}" == *:* ]]; then
   # PCI devices - format as rootDevices array
   if [[ "${DEVICE_LST}" == *,* ]]; then
       # Multiple devices - split and format as YAML array
       DEVICE_ARRAY=$(echo "${DEVICE_LST}" | sed 's/,/", "/g')
       DEVICES='rootDevices: [ "'${DEVICE_ARRAY}'" ]'
   else
       # Single device
       DEVICES='rootDevices: [ "'${DEVICE_LST}'" ]'
   fi
else
   # Interface names - format as pfNames array  
   if [[ "${DEVICE_LST}" == *,* ]]; then
       # Multiple interfaces - split and format as YAML array
       DEVICE_ARRAY=$(echo "${DEVICE_LST}" | sed 's/,/", "/g')
       DEVICES='pfNames: [ "'${DEVICE_ARRAY}'" ]'
   else
       # Single interface
       DEVICES='pfNames: [ "'${DEVICE_LST}'" ]'
   fi
fi
cat << HEREDOC
---
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: ${NETWORK_NAME}
  namespace: ${NETOP_NAMESPACE}
spec:
  deviceType: netdevice
  nicSelector:
    vendor: "15b3"
    ${DEVICES}
  numVfs: ${NUM_VFS}
  linkType: IB
  priority: 90    # used to resolve multiple policy definitions, lower value, higher priority
  isRdma: true
  resourceName: ${NETOP_RESOURCE}_${NIDX}
  nodeSelector:
    ${NETOP_NODESELECTOR}: "${NETOP_NODESELECTOR_VAL}"
    feature.node.kubernetes.io/pci-15b3.present: "true"
HEREDOC
