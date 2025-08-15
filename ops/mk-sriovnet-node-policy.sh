#!/bin/bash 
#
# https://github.com/k8snetworkplumbingwg/sriov-network-operator/tree/master
#
if [ "$#" -lt 3 ];then
  echo "usage:$0 {NETWORK_NDIX} {DEVICE_LST} {SCALABLE_UNIT}"
  echo "example:$0 a 0000:24:00.0 su-1"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
NDIX="${1}"
shift
DEVICE_LST="${1}"
shift
NETOP_SU="${1}"
shift

logger "DEVICE_LST[${DEVICE_LST}]"
if [[ "${DEVICE_LST}" == *:* ]];then
   DEVICES='rootDevices: [ "'${DEVICE_LST}'" ]'
else
   DEVICES='pfNames: [ "'${DEVICE_LST}'" ]'
fi
cat << HEREDOC
---
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: ${NETOP_NETWORK_NAME}-node-policy-${NDIX}-${NETOP_SU}
  namespace: ${NETOP_NAMESPACE}
spec:
  deviceType: netdevice
  mtu: ${NETOP_MTU}
  nicSelector:
    vendor: "15b3"
    ${DEVICES}
  numVfs: ${NUM_VFS}
  linkType: ETH
  priority: 90    # used to resolve multiple policy definitions, lower value, higher priority
  isRdma: true
  resourceName: ${NETOP_RESOURCE}_${NDIX}
  nodeSelector:
    ${NETOP_NODESELECTOR}: "${NETOP_NODESELECTOR_VAL}"
    feature.node.kubernetes.io/pci-15b3.present: "true"
HEREDOC
