#!/bin/bash
#
# https://github.com/k8snetworkplumbingwg/sriov-network-operator/tree/master
#
if [ "$#" -lt 3 ];then
  echo "usage:$0 {NETWORK_NDIX} {PCI_DEVICE_LST} ${SCALABLE_UNIT}"
  echo "example:$0 a 0000:24:00.0 su-1"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
NDIX="${1}"
PCI_DEVICE_LST="${2}"
NETOP_SU="${3}"

FILE="${NETOP_NETWORK_NAME}-node-policy-${NDIX}-${NETOP_SU}.yaml"
cat << HEREDOC > ${FILE}
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: ${FILE%%.yaml}
  namespace: ${NETOP_NAMESPACE}
spec:
  deviceType: netdevice
  mtu: 1500
  nicSelector:
    vendor: "15b3"
    rootDevices: [ "${PCI_DEVICE_LST}" ]
  numVfs: 8
  linkType: ETH
  priority: 90    # used to resolve multiple policy definitions, lower value, higher priority
  isRdma: true
  resourceName: ${NETOP_RESOURCE}_${NDIX}
  nodeSelector:
    node-role.kubernetes.io/worker: ""
     feature.node.kubernetes.io/pci-15b3.present: "true"
HEREDOC
echo ${FILE}
