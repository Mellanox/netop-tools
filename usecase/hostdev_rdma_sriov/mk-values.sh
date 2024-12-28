#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
cat <<HEREDOC1>./values.yaml
nfd:
  enabled: true
#sriovNetworkOperator:
#  enabled: false
HEREDOC1
if [ "${PROD_VER}" = "0" ];then
cat <<HEREDOC2>>./values.yaml
  imagePullSecrets: [ngc-image-secret]   # <- specify your created pull secrets for ngc private repo

# NicClusterPolicy CR values:
imagePullSecrets: [ngc-image-secret]   # <- specify your created pull secrets for ngc private repo
HEREDOC2
fi
#if [ "${IPAM_TYPE}" = "nv-ipam" ];then
#  NVIPAMVAL=true
#  IPAMVAL=false
#else
#  NVIPAMVAL=false
#  IPAMVAL=true
#fi
cat <<HEREDOC3>>./values.yaml
# NicClusterPolicy CR values
deployCR: true
#nvIpam:
#  deploy: ${NVIPAMVAL}

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
#rdmaSharedDevicePlugin:
#  deploy: false
#
#sriovDevicePlugin:
#  deploy: true
#  resources:
#HEREDOC3
#for DEVDEF in ${NETOP_NETLIST[@]};do
#  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
#  DEVICEID=`echo ${DEVDEF}|cut -d',' -f2`
#  NETOP_HCAMAX=`echo ${DEVDEF}|cut -d',' -f3`
#  DEVNAMES=`echo ${DEVDEF}|cut -d',' -f4-12`
#  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
#echo "    - name: ${NETOP_RESOURCE}_${NIDX}" >>./values.yaml
#  if [ "${NETOP_VENDOR}" != "" ];then
#echo "      vendors: [${NETOP_VENDOR}]" >>./values.yaml
#  fi
#  if [ "${DEVICEID}" != "" ];then
#echo "      deviceIDs: [${DEVICEID}]" >>./values.yaml
#  fi
#  if [ "${DEVNAMES}" != "" ];then
#    if [[ ${DEVNAMES} == *:* ]]; then
#echo "      pciAddresses: [\"${DEVNAMES}\"]" >>./values.yaml
#    else
##echo "      pfNames: [\"${DEVNAMES}\"]" >>./values.yaml
#echo "      pfNames: [\"${DEVNAMES}\"] unsupported use pciAddresses: selector"
#      exit 1
#    fi
#  fi
#done
#cat <<HEREDOC4>>./values.yaml
#secondaryNetwork:
#  deploy: true
#  multus:
#    deploy: true
#  cniPlugins:
#    deploy: true
#  ipamPlugin:
#    deploy: ${IPAMVAL}
#HEREDOC4
