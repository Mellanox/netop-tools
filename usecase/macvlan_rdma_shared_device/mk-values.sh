#!/bin/bash
#
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"

function rdmaSharedDevicePlugin()
{
cat << RDMA_SHARED_DEVICE_PLUGIN1
rdmaSharedDevicePlugin:
  deploy: true
  resources:
RDMA_SHARED_DEVICE_PLUGIN1
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  DEVICEID=`echo ${DEVDEF}|cut -d',' -f2`
  NETOP_HCAMAX=`echo ${DEVDEF}|cut -d',' -f3`
  DEVNAMES=`echo ${DEVDEF}|cut -d',' -f4-12`
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
echo "    - name: ${NETOP_RESOURCE}_${NIDX}" >>./values.yaml
  if [ "${NETOP_VENDOR}" != "" ];then
echo "      vendors: [${NETOP_VENDOR}]" >>./values.yaml
  fi
  if [ "${DEVICEID}" != "" ];then
echo "      deviceIDs: [${DEVICEID}]" >>./values.yaml
  fi
  if [ "${NETOP_HCAMAX}" != "" ];then
echo "      rdmaHcaMax: ${NETOP_HCAMAX}" >>./values.yaml
  fi
  if [ "${DEVNAMES}" != "" ];then
    if [[ ${DEVNAMES} == *:* ]]; then
      echo "PCIe:BFD device id not supported by rdmaSharedDevicePlugin"
    else
echo "      ifNames: [\"${DEVNAMES}\"]" >>./values.yaml
echo "      linkTypes: [\"ether\"]" >>./values.yaml
    fi
  fi
done
# config: |
#   {
#     "configList": [
#       {
#         "resourceName": "rdma_shared_device_a",
#         "resourcePrefix": "nvidia.com",
#         "rdmaHcaMax": 70,
#         "selectors": {
#           "vendors": [],
#           "deviceIDs": [],
#           "drivers": [],
#           "ifNames": ["ens1f0np0"],
#           "linkTypes": ["ether"]
#         }
#       }
#     ]
#   }
}
cat <<HEREDOC1>./values.yaml
nfd:
  enabled: true
sriovNetworkOperator:
  enabled: false
HEREDOC1
if [ "${PROD_VER}" = "0" ];then
cat <<HEREDOC2>>./values.yaml
  imagePullSecrets: [ngc-image-secret]   # <- specify your created pull secrets for ngc private repo

# NicClusterPolicy CR values:
imagePullSecrets: [ngc-image-secret]   # <- specify your created pull secrets for ngc private repo
HEREDOC2
fi
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  NVIPAMVAL=true
  IPAMVAL=false
else
  NVIPAMVAL=false
  IPAMVAL=true
fi
cat <<HEREDOC3>>./values.yaml
# NicClusterPolicy CR values:
deployCR: true
nvIpam:
  deploy: ${NVIPAMVAL}

ofedDriver:
  deploy: true
  env:
  - name: RESTORE_DRIVER_ON_POD_TERMINATION
    value: "true"
  - name: UNLOAD_STORAGE_MODULES
    value: "true"
  - name: CREATE_IFNAMES_UDEV
    value: "true"
HEREDOC3
rdmaSharedDevicePlugin >>./values.yaml
cat <<HEREDOC4>>./values.yaml

sriovDevicePlugin:
  deploy: false

secondaryNetwork:
  deploy: true
  multus:
    deploy: true
  cniPlugins:
    deploy: true
  ipamPlugin:
    deploy: ${IPAMVAL}
HEREDOC4
