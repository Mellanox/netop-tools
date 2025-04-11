#!/bin/bash
#
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
for DEVICE_TYPE in ${DEVICE_TYPES[@]};do
  case ${DEVICE_TYPE} in
  connectx-4)
    NIC_TYPE=1013
    ;;
  connectx-4lx)
    NIC_TYPE=1015
    ;;
  connectx-5)
    NIC_TYPE=1017
    ;;
  connectx-5-ex)
    NIC_TYPE=1019
    ;;
  connectx-6)
    NIC_TYPE=101b
    ;;
  connectx-6dx)
    NIC_TYPE=101d
    ;;
  connectx-6lx)
    NIC_TYPE=101f
    ;;
  connectx-7)
    NIC_TYPE=1021
    ;;
  connectx-8)
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
    ROCE_OPTIMIZED="true"
    ;;
  sriovibnet_rdma|ipoib_rdma_shared_device)
    LINK_TYPE="Infiniband"
    ROCE_OPTIMIZED="false"
    ;;
  esac
  FILE="nic-config-crd-${DEVICE_TYPE}.yaml"
cat << NIC_CONFIG0 > ${FILE}
apiVersion: configuration.net.nvidia.com/v1alpha1
kind: NicConfigurationTemplate
metadata:
   name: ${DEVICE_TYPE}-config
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
      numVfs: ${NUM_VFS}
      linkType: ${LINK_TYPE}
      pciPerformanceOptimized:
         enabled: true
         maxAccOutRead: 44
         maxReadRequest: 4096
      roceOptimized:
         enabled: ${ROCE_OPTIMIZED}
NIC_CONFIG0
if [ "${ROCE_OPTIMIZED}" = "true" ];then
cat << NIC_CONFIG1 >> ${FILE}
         qos:
           trust: dscp
           pfc: "0,0,0,1,0,0,0,0"
NIC_CONFIG1
fi
cat << NIC_CONFIG2 >> ${FILE}
      gpuDirectOptimized:
         enabled: true
         env: Baremetal
NIC_CONFIG2
done
