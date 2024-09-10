#!/bin/bash
#
# https://github.com/k8snetworkplumbingwg/sriov-network-operator/tree/master
#
if [ "$#" -lt 2 ];then
  echo "usage:$0 {NETWORK_NDIX} {PCI_DEVICE_LST}"
  echo "example:$0 a 0000:24:00.0"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
NDIX="${1}"
shift
PCI_DEVICE_LST="${1}"
shift

cat << HEREDOC > ./sriovnet-node-policy-${NDIX}.yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: policy-${NDIX}
  namespace: ${NETOP_NAMESPACE}
spec:
  deviceType: netdevice
  mtu: 9000
  nicSelector:
    vendor: "15b3"
    deviceID: "101b"
    rootDevices: [ "${PCI_DEVICE_LST}" ]
  numVfs: 8
  priority: 90    # used to resolve multiple policy definitions, lower value, higher priority
  isRdma: true
  resourceName: ${NETOP_RESOURCE}_${NDIX}
  nodeSelector:
    node-role.kubernetes.io/worker: ""
HEREDOC
