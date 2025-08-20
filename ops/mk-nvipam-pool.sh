#!/bin/bash
#
# define nvipam resources
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function nv_ippool()
{
IPPOOL_NAME="${1}"
shift
NETWORK_RANGE="${1}"
shift
NETWORK_GW="${1}"
shift
PERNODE_BLOCKSIZE="${1}"
shift
cat <<POOLHEREDOC0
---
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
  name: ${IPPOOL_NAME}
  namespace: ${NETOP_NAMESPACE}
spec:
  subnet: ${NETWORK_RANGE}
  perNodeBlockSize: ${PERNODE_BLOCKSIZE}
POOLHEREDOC0
if [ "${NETWORK_GW}" != "" ];then
cat <<POOLHEREDOC1
  gateway: ${NETWORK_GW}
POOLHEREDOC1
fi
cat <<POOLHEREDOC2
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
      - key: ${NETOP_NODESELECTOR}
        operator: Exists
POOLHEREDOC2
#     - key: node.su/${NETOP_SU}
#       operator: Exists
}
nv_ippool ${*}
