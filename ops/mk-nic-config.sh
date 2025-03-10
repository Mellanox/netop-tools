#!/bin/bash
#
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
if $# -lt 1 ];then
  echo "usage:$0 connectx4|connectx4lx|connectx5|connectx5-ex|connectx6|connectx6dx|connectx6lx|connect7|connectx8|bf2|bf3"
  exit 1
fi
case ${DEVICE_TYPE} in
connectx4)
  NIC_TYPE=1013
  ;;
connectx4lx)
  NIC_TYPE=1015
  ;;
connectx5)
  NIC_TYPE=1017
  ;;
connectx5-ex)
  NIC_TYPE=1019
  ;;
connectx6)
  NIC_TYPE=101b
  ;;
connectx6dx)
  NIC_TYPE=101d
  ;;
connectx6lx)
  NIC_TYPE=101f
  ;;
connectx7)
  NIC_TYPE=1021
  ;;
connectx8)
  NIC_TYPE=1023
  ;;
bf2)
  NIC_TYPE=a2d6
  ;;
bf3)
  NIC_TYPE=a2dc
  ;;
esac
case ${USECASE} in
hostdev_rdma_sriov|sriovnet_rdma|macvlan_rdma_shared_device)
  LINK_TYPE="Ethernet"
  ;;
sriovibnet_rdma|ipoib_rdma_shared_device)
  LINK_TYPE="Infiniband"
  ;;
esac
FILE="nic-config-crd.yaml"
cat << NIC_CONFIG > ${FILE}
apiVersion: configuration.net.nvidia.com/v1alpha1
kind: NicConfigurationTemplate
metadata:
   name: connectx6-config
   #namespace: nic-configuration-operator
   namespace: ${NETOP_NAMESPACE}
spec:
   nodeSelector:
      feature.node.kubernetes.io/network-sriov.capable: "true"
   nicSelector:
      # nicType selector is mandatory the rest are optional. Only a single type can be specified.
      nicType: ${NIC_TYPE}
#      pciAddresses:
#         - "0000:07:00.0"
#         - “0000:08:00.0”
#      serialNumbers:
#         - "mt1910x14362"
   resetToDefault: false # if set, template is ignored, device configuration should reset
   template:
      # numVfs and linkType fields are mandatory, the rest are optional
      numVfs: 0
      linkType: ${LINK_TYPE}
      pciPerformanceOptimized:
         enabled: true
         maxAccOutRead: 44
         maxReadRequest: 4096
      roceOptimized:
         enabled: true
#
#        qos:
#           trust: dscp
#           pfc: "0,0,0,1,0,0,0,0"
      gpuDirectOptimized:
         enabled: true
         env: Baremetal
NIC_CONFIG
