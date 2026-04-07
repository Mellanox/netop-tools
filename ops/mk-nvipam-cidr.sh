#!/bin/bash
#
# define nvipam CIDRPool resource - writes to stdout
# Args: IPPOOL_NAME NETWORK_RANGE GATEWAY_INDEX PER_NODE_PREFIX
#
# Called from mk-network-cr.sh as:
#   mk-nvipam-cidr.sh "${IPPOOL_NAME}" "${RANGE}" "${GW}" "${NETOP_PERNODE_BLOCKSIZE}" >> ${FILE}
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"
IPPOOL_NAME="${1}"
NETWORK_RANGE="${2}"
GATEWAY_INDEX="${3}"
PER_NODE_PREFIX="${4}"

cat <<POOLHEREDOC
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: CIDRPool
metadata:
  name: ${IPPOOL_NAME}
  namespace: ${NETOP_NAMESPACE}
spec:
  cidr: ${NETWORK_RANGE}
  gatewayIndex: ${GATEWAY_INDEX}
  perNodeNetworkPrefix: ${PER_NODE_PREFIX}
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
        - key: ${NETOP_NODESELECTOR}
          operator: Exists
#       - key: node.su/${NETOP_SU}
#         operator: Exists
POOLHEREDOC
