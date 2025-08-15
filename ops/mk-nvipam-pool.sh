#!/bin/bash
#
# define nvipam resources
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function nv_ippool()
{
NIDX=${1}
shift
NETOP_SU=${1}
shift
NETWORK_RANGE=${1}
shift
NETWORK_GW=${1}
shift
PERNODE_BLOCKSIZE=${1}
shift
cat <<POOLHEREDOC
---
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: ${NETOP_NETWORK_POOL}-${NIDX}-${NETOP_SU}
  namespace: ${NETOP_NAMESPACE}
spec:
  subnet: ${NETWORK_RANGE}
  perNodeBlockSize: ${PERNODE_BLOCKSIZE}
  gateway: ${NETWORK_GW}
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
      - key: ${NETOP_NODESELECTOR}
        operator: Exists
#     - key: node.su/${NETOP_SU}
#       operator: Exists
POOLHEREDOC
}
nv_ippool ${*}
