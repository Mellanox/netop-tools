#!/bin/bash -xe
#
# define nvipam resources
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function nv_cidrpool()
{
FILE=${1}
shift
NIDX=${1}
shift
NETOP_SU=${1}
shift
NETWORK_RANGE=${1}
shift
NETWORK_GW_IDX=${1}
shift
NETWORK_PREFIX=${1}
shift
cat <<POOLHEREDOC > ${FILE}
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: CIDRPool
metadata:
  name: ${NETOP_NETWORK_POOL}-${NIDX}-${NETOP_SU}
  namespace: ${NETOP_NAMESPACE}
spec:
  cidr: ${NETWORK_RANGE}
  gatewayIndex: ${NETWORK_GW_IDX}
  perNodeNetworkPrefix: ${NETWORK_PREFIX}
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
        - key: node-role.kubernetes.io/worker
          operator: Exists
#       - key: node.su/${NETOP_SU}
#         operator: Exists
POOLHEREDOC
}
nv_cidrpool ${*}
#
#cat <<HEREDOC2> "${FILE}"
#apiVersion: nv-ipam.nvidia.com/v1alpha1
#kind: CIDRPool
#metadata:
#  name: ${NETOP_NETWORK_POOL}-${NIDX}-${NETOP_SU}
#  namespace: ${NETOP_NAMESPACE}
#spec:
#  cidr: ${NETWORK_RANGE}
#  gatewayIndex: 1
#  perNodeNetworkPrefix: 24
#  exclusions: # optional
#    - startIP: 192.169.0.1
#      endIP: 192.169.0.255
#  staticAllocations:
#    - nodeName: node-33
#      prefix: 192.169.33.0/24
#      gateway: 192.169.33.1
#    - prefix: 192.169.1.0/24
#  nodeSelector: # optional
#    nodeSelectorTerms:
#      - matchExpressions:
#          - key: node-role.kubernetes.io/worker
#            operator: Exists
#  defaultGateway: true # optional
#  routes: # optional
#  - dst: 5.5.0.0/24
#HEREDOC2
