#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
set -x
function sriovNetworkOperator()
{
case ${USECASE} in
sriovnet_rdma|sriovibnet_rdma)
  SRIOVNET="true"
  ;;
*)
  SRIOVNET="false"
esac
cat << SRIOV_NETWORK_OPERATOR
sriovNetworkOperator:
  enabled: ${SRIOVNET}
SRIOV_NETWORK_OPERATOR
}
function pullSecrets()
{
if [ "${PROD_VER}" = "0" ];then
cat <<PULL_SECRETS
  imagePullSecrets: [ngc-image-secret]   # <- specify your created pull secrets for ngc private repo

# NicClusterPolicy CR values:
imagePullSecrets: [ngc-image-secret]   # <- specify your created pull secrets for ngc private repo
PULL_SECRETS
fi
}
function ipamType()
{
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  NVIPAMVAL=true
  IPAMVAL=false
else
  NVIPAMVAL=false
  IPAMVAL=true
fi
}

function values_yaml()
{
cat <<VALUES_YAML
nfd:
  enabled: true
# NicClusterPolicy CR values
deployCR: true
nvIpam:
  deploy: ${NVIPAMVAL}
VALUES_YAML
}
function ofedDriver()
{
cat << OFED_DRIVER
ofedDriver:
  deploy: true
  env:
  - name: RESTORE_DRIVER_ON_POD_TERMINATION
    value: "true"
  - name: UNLOAD_STORAGE_MODULES
    value: "true"
  - name: CREATE_IFNAMES_UDEV
    value: "true"
OFED_DRIVER
}
function rdmaSharedDevicePlugin()
{
case ${USECASE} in
macvlan_rdma_shared_device)
cat << RDMA_SHARED_DEVICE_PLUGIN1
rdmaSharedDevicePlugin:
  deploy: true
  resources:
RDMA_SHARED_DEVICE_PLUGIN1
  ;;
*)
cat << RDMA_SHARED_DEVICE_PLUGIN2
rdmaSharedDevicePlugin:
  deploy: false
RDMA_SHARED_DEVICE_PLUGIN2
  return
  ;;
esac
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  DEVICEID=`echo ${DEVDEF}|cut -d',' -f2`
  NETOP_HCAMAX=`echo ${DEVDEF}|cut -d',' -f3`
  DEVNAMES=`echo ${DEVDEF}|cut -d',' -f4-12`
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
echo "    - name: ${NETOP_RESOURCE}_${NIDX}"
  if [ "${NETOP_VENDOR}" != "" ];then
echo "      vendors: [${NETOP_VENDOR}]"
  fi
  if [ "${DEVICEID}" != "" ];then
echo "      deviceIDs: [${DEVICEID}]"
  fi
  if [ "${NETOP_HCAMAX}" != "" ];then
echo "      rdmaHcaMax: ${NETOP_HCAMAX}"
  fi
  if [ "${DEVNAMES}" != "" ];then
    if [[ ${DEVNAMES} == *:* ]]; then
      echo "PCIe:BFD device id not supported by rdmaSharedDevicePlugin"
    else
echo "      ifNames: [\"${DEVNAMES}\"]"
echo "      linkTypes: [\"ether\"]"
    fi
  fi
done
}
function sriovDevicePlugin()
{
case ${USECASE} in
hostdev_rdma_sriov)
cat << SRIOV_DEVICE_PLUGIN1
sriovDevicePlugin:
  deploy: true
  resources:
SRIOV_DEVICE_PLUGIN1
  ;;
*)
cat << SRIOV_DEVICE_PLUGIN2
sriovDevicePlugin:
  deploy: false
SRIOV_DEVICE_PLUGIN2
  return
  ;;
esac
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  DEVICEID=`echo ${DEVDEF}|cut -d',' -f2`
  NETOP_HCAMAX=`echo ${DEVDEF}|cut -d',' -f3`
  DEVNAMES=`echo ${DEVDEF}|cut -d',' -f4-12`
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
echo "    - name: ${NETOP_RESOURCE}_${NIDX}"
  if [ "${NETOP_VENDOR}" != "" ];then
echo "      vendors: [${NETOP_VENDOR}]"
  fi
  if [ "${DEVICEID}" != "" ];then
echo "      deviceIDs: [${DEVICEID}]"
  fi
  if [ "${DEVNAMES}" != "" ];then
    if [[ ${DEVNAMES} == *:* ]]; then
echo "      pciAddresses: [\"${DEVNAMES}\"]"
    else
echo "      pfNames: [\"${DEVNAMES}\"] unsupported use pciAddresses: selector"
      exit 1
    fi
  fi
done
}
function secondaryNetwork()
{
cat << SECONDARY_NETWORK
secondaryNetwork:
  deploy: true
  multus:
    deploy: true
  cniPlugins:
    deploy: true
  ipamPlugin:
    deploy: ${IPAMVAL}
SECONDARY_NETWORK
}
function 24_7_0()
{
  ipamType
  values_yaml
  sriovNetworkOperator
  pullSecrets
  ofedDriver
  rdmaSharedDevicePlugin
  sriovDevicePlugin
  secondaryNetwork
}
function 24_10_0()
{
  ipamType
  values_yaml
  sriovNetworkOperator
  pullSecrets
# ofedDriver
}
function 24_10_1()
{
  ipamType
  values_yaml
  sriovNetworkOperator
  pullSecrets
# ofedDriver
}
NETOP_FUNCT=$(echo ${NETOP_VERSION} | sed 's/\./_/g')
${NETOP_FUNCT} > ./values.yaml
