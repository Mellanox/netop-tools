#!/bin/bash
#
# nic cluster plocy file has migrated outof the values.yaml file
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
case ${NETOP_VERSION} in
24.10.0)
  DOCA_VERSION="24.10-0.7.0.0-0"
  SRIOV_DP_VERSION="v3.8.0"
  RDMA_SDP_VERSION="v1.5.2"
  IPOIB_VERSION="v1.2.0"
  CNI_PLUGINS_VERSION="v1.5.0"
  MULTUS_VERSION="v4.1.0"
  WHEREABOUTS_VERSION="v0.7.0"
  NVIPAM_VERSION="v0.2.0"
  ;;
24.10.1)
  DOCA_VERSION="24.10-0.7.0.0-0"
  SRIOV_DP_VERSION="v3.8.0"
  RDMA_SDP_VERSION="v1.5.2"
  IPOIB_VERSION="v1.2.0"
  CNI_PLUGINS_VERSION="v1.5.0"
  MULTUS_VERSION="v4.1.0"
  WHEREABOUTS_VERSION="v0.7.0"
  NVIPAM_VERSION="v0.2.0"
  ;;
esac
function ofedDriver()
{
cat << OFED_DRIVER
  ofedDriver:
    image: doca-driver
    repository: nvcr.io/nvidia/mellanox
    version: ${DOCA_VERSION}
    forcePrecompiled: false
    imagePullSecrets: []
    terminationGracePeriodSeconds: 300
    startupProbe:
      initialDelaySeconds: 10
      periodSeconds: 20
    livenessProbe:
      initialDelaySeconds: 30
      periodSeconds: 30
    readinessProbe:
      initialDelaySeconds: 10
      periodSeconds: 30
    upgradePolicy:
      autoUpgrade: true
      maxParallelUpgrades: 1
      safeLoad: false
      drain:
        enable: true
        force: true
        podSelector: ""
        timeoutSeconds: 300
        deleteEmptyDir: true
OFED_DRIVER
}
function sriovDevicePlugin()
{
cat << SRIOV_DEV_PLUGIN1
  sriovDevicePlugin:
    image: sriov-network-device-plugin
    repository: ghcr.io/k8snetworkplumbingwg
    version: ${SRIOV_DP_VERSION}
    imagePullSecrets: []
    config: |
      {
        "resourceList": [
SRIOV_DEV_PLUGIN1
NETWORKS=${#NETOP_NETLIST[@]}
COMMA=","
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  DEVICEID=`echo ${DEVDEF}|cut -d',' -f2`
  NETOP_HCAMAX=`echo ${DEVDEF}|cut -d',' -f3`
  DEVNAMES=`echo ${DEVDEF}|cut -d',' -f4-12`
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
  let NETWORKS=NETWORKS-1
  if [ ${NETWORKS} -le 0 ];then
	  COMMA=""
  fi
cat << SRIOV_DEV_PLUGIN2
          {
            "resourcePrefix": "nvidia.com",
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              "devices": [],
              "drivers": [],
              "pfNames": [],
              "pciAddresses": ["${DEVNAMES}"],
              "rootDevices": [],
              "linkTypes": ["${LINK_TYPES}],
              "isRdma": true
            }
          }${COMMA}
SRIOV_DEV_PLUGIN2
done
cat << SRIOV_DEV_PLUGIN3
        ]
      }
SRIOV_DEV_PLUGIN3
}
function rdmaSharedDevicePlugin()
{
cat << RDMA_SDP1
rdmaSharedDevicePlugin:
     # [map[ifNames:[ibs1f0] name:rdma_shared_device_a]]
     image: k8s-rdma-shared-dev-plugin
     repository: ghcr.io/mellanox
     version: ${RDMA_SDP_VERSION}
     imagePullSecrets: []
     # The config below directly propagates to k8s-rdma-shared-device-plugin configuration.
     # Replace 'devices' with your (RDMA capable) netdevice name.
     config: |
       {
RDMA_SDP1
NETWORKS=${#NETOP_NETLIST[@]}
COMMA=","
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  DEVICEID=`echo ${DEVDEF}|cut -d',' -f2`
  NETOP_HCAMAX=`echo ${DEVDEF}|cut -d',' -f3`
  DEVNAMES=`echo ${DEVDEF}|cut -d',' -f4-12`
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
  let NETWORKS=NETWORKS-1
  if [ ${NETWORKS} -le 0 ];then
    COMMA=""
  fi
cat << RDMA_SDP2
         "configList": [
          {
            "resourcePrefix": "nvidia.com",
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "rdmaHcaMax": ${NETOP_HCAMAX},
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              "drivers": [],
              "ifNames": [${DEVNAMES}],
              "linkTypes": ["${LINK_TYPES}"],
              "isRdma": true
            }
          }${COMMA}
RDMA_SDP2
done
cat << RDMA_SDP3
        ]
      }
RDMA_SDP3
}
function secondaryNetwork()
{
cat << SECONDARY_NETWORK1
  secondaryNetwork:
    cniPlugins:
      image: plugins
      repository: ghcr.io/k8snetworkplumbingwg
      version: ${CNI_PLUGINS_VERSION}
      imagePullSecrets: []
    multus:
      image: multus-cni
      repository: ghcr.io/k8snetworkplumbingwg
      version: ${MULTUS_VERSION}
      imagePullSecrets: []
SECONDARY_NETWORK1
if [ "${IPAM_TYPE}" = "whereabouts" ];then
cat << SECONDARY_NETWORK2 >> ${FILE}
    ipamPlugin:
      image: whereabouts
      repository: ghcr.io/k8snetworkplumbingwg
      version: ${WHEREABOUTS_VERSION}
      imagePullSecrets: []
SECONDARY_NETWORK2
fi
}
function nvIpam()
{
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
cat << NVIPAM
  nvIpam:
    image: nvidia-k8s-ipam
    imagePullSecrets: []
    repository: ghcr.io/mellanox
    version: ${NVIPAM_VERSION}
    enableWebhook: false
NVIPAM
fi
}
FILE="NicClusterPolicy.yaml"
cat << HEREDOC1 > ${FILE}
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: nic-cluster-policy
spec:
HEREDOC1
ofedDriver >> ${FILE}
case ${USECASE} in
ipoib_rdma_shared_device)
  LINK_TYPES="IB"
  rdmaSharedDevicePlugin >> ${FILE}
  ;;
macvlan_rdma_shared_device)
  LINK_TYPES="ether"
  rdmaSharedDevicePlugin >> ${FILE}
  ;;
hostdev_rdma_sriov)
  sriovDevicePlugin >> ${FILE}
  ;;
esac
secondaryNetwork >> ${FILE}
nvIpam >> ${FILE}
