#!/bin/bash
#
# nic cluster policy file has migrated out of the values.yaml file
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function init_file()
{
  if [ "${NETOP_TAG_VERSION}" == true ];then
    echo "# VERSION:${NETOP_VERSION}" > "${1}"
  else
    rm -f "${1}"
  fi
}
function get_container()
{
  while read LINE;do
    CONTAINER=$(echo ${LINE}|cut -d, -f4)
    if [ "${CONTAINER}" == "${1}" ];then
       echo "${LINE}"
    fi
  done <"${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
}
function get_repository()
{
  LINE=$(get_container ${1})
  REPOSITORY=$(echo "${LINE}" | cut -d, -f3)
  if [ "${2}" = "required" ] &&  [ "${REPOSITORY}" = "" ];then
    echo "required repository ${1} not found in container list ${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
    exit 1
  fi
  echo ${REPOSITORY}
}
function get_release_tag()
{
  LINE=$(get_container ${1})
  echo "${LINE}" | cut -d, -f5
}
function ofedDriver()
{
if [ "${OFED_ENABLE}" != true ];then
  return
fi
cat << OFED_DRIVER0
  ofedDriver:
    image: doca-driver
OFED_DRIVER0
if [ "${NETOP_JINGA_CONFIG}" == "true" ];then
cat << OFED_DRIVER1
    repository: {{registry or "nvcr.io"}}/nvidia/mellanox
OFED_DRIVER1
else
   #repository: nvcr.io/nvidia/mellanox
cat << OFED_DRIVER2
    repository: $(get_repository doca-driver required)
OFED_DRIVER2
fi
    #version: ${DOCA_VERSION}
cat << OFED_DRIVER3
    version: $(get_release_tag doca-driver)
    forcePrecompiled: false
    imagePullSecrets: []
    terminationGracePeriodSeconds: 300
    env:
    - name: RESTORE_DRIVER_ON_POD_TERMINATION
      value: "true"
    - name: UNLOAD_STORAGE_MODULES
      value: "true"
    - name: CREATE_IFNAMES_UDEV
      value: "true"
OFED_DRIVER3
    #
    # should be fixed in 25.4.0
    #
    if [ "${OFED_BLACKLIST_ENABLE}" = "true" ];then
cat << OFED_DRIVER4
    - name: OFED_BLACKLIST_MODULES_FILE
      value: "/host/etc/modprobe.d/blacklist-ofed-modules.conf"
OFED_DRIVER4
    fi
    if [ "${OFED_BLACKLIST_ADD}" != "" ];then
cat << OFED_DRIVER5
    - name:  OFED_BLACKLIST_MODULES
      value: "mlx5_core:mlx5_ib:ib_umad:ib_uverbs:ib_ipoib:rdma_cm:rdma_ucm:ib_core:ib_cm:${OFED_BLACKLIST_ADD}"
OFED_DRIVER5
    fi
    if [ "${ENABLE_NFSRDMA}" = "true" ];then
cat << OFED_DRIVER6
    - name: ENABLE_NFSRDMA
      value: "${ENABLE_NFSRDMA}"
OFED_DRIVER6
    fi
cat << OFED_DRIVER7
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
OFED_DRIVER7
}
function sriovDevicePlugin()
{
cat << SRIOV_DEV_PLUGIN1
  sriovDevicePlugin:
    image: sriov-network-device-plugin
    repository: $(get_repository sriov-network-device-plugin required)
    version: $(get_release_tag sriov-network-device-plugin)
    imagePullSecrets: []
    config: |
      {
        "resourceList": [
SRIOV_DEV_PLUGIN1
NETWORKS=${#NETOP_NETLIST[@]}
COMMA=","
for DEVDEF in ${NETOP_NETLIST[@]};do
  IFS=',' read NIDX DEVICEID NETOP_HCAMAX DEVNAMES <<< ${DEVDEF}
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
  let NETWORKS=NETWORKS-1
  if [ ${NETWORKS} -le 0 ];then
	  COMMA=""
  fi
  if [[ "${DEVNAMES}" == *:* ]];then
     PCI_ADDRS='"pciAddresses": ["'${DEVNAMES}'"]'
     PF_NAMES='"pfNames": []'
  else
     PCI_ADDRS='"pciAddresses": []'
     PF_NAMES='"pfNames": [ "'${DEVNAMES}'" ]'
  fi
cat << SRIOV_DEV_PLUGIN2
          {
            "resourcePrefix": "nvidia.com",
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              "devices": [],
              "drivers": [],
              ${PF_NAMES},
              ${PCI_ADDRS},
              "rootDevices": [],
              "linkTypes": [${LINK_TYPES}],
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
    image: k8s-rdma-shared-dev-plugin
    repository: $(get_repository k8s-rdma-shared-dev-plugin required)
    version: $(get_release_tag k8s-rdma-shared-dev-plugin)
    imagePullSecrets: []
    # The config below directly propagates to k8s-rdma-shared-device-plugin configuration.
    # Replace 'devices' with your (RDMA capable) netdevice name.
    config: |
      {
        "configList": [
RDMA_SDP1
NETWORKS=${#NETOP_NETLIST[@]}
COMMA=","
for DEVDEF in ${NETOP_NETLIST[@]};do
  IFS=',' read NIDX DEVICEID NETOP_HCAMAX DEVNAMES <<< ${DEVDEF}
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
  let NETWORKS=NETWORKS-1
  if [ ${NETWORKS} -le 0 ];then
    COMMA=""
  fi
#           "resourcePrefix": "nvidia.com",
cat << RDMA_SDP2
          {
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "rdmaHcaMax": ${NETOP_HCAMAX},
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              "drivers": [],
              "ifNames": ["${DEVNAMES}"],
              "linkTypes": [${LINK_TYPES}],
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
      repository: $(get_repository plugins required)
      version: $(get_release_tag plugins)
      imagePullSecrets: []
    multus:
      image: multus-cni
      repository: $(get_repository multus-cni required)
      version: $(get_release_tag multus-cni)
      imagePullSecrets: []
SECONDARY_NETWORK1
if [ "${NETOP_BCM_CONFIG}" == true ];then
cat << SECONDARY_NETWORK2
      containerResources:
        - name: "kube-multus"
          limits: {memory: "100Mi"}
          requests: {memory: "100Mi"}
SECONDARY_NETWORK2
fi
case "${NETOP_NETWORK_TYPE}" in
IPoIBNetwork)
cat << SECONDARY_NETWORK3
    ipoib:
      image: ipoib-cni
      repository: $(get_repository ipoib-cni required)
      version: $(get_release_tag ipoib-cni)
      imagePullSecrets: []
SECONDARY_NETWORK3
    ;;
esac
if [ "${IPAM_TYPE}" = "whereabouts" ];then
cat << SECONDARY_NETWORK4 >> ${FILE}
    ipamPlugin:
      image: whereabouts
      repository: $(get_repository whereabouts required)
      version: $(get_release_tag whereabouts)
      imagePullSecrets: []
SECONDARY_NETWORK4
fi
}
function nvIpam()
{
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
cat << NVIPAM
  nvIpam:
    image: nvidia-k8s-ipam
    repository: $(get_repository nvidia-k8s-ipam required)
    version: $(get_release_tag nvidia-k8s-ipam)
    imagePullSecrets: []
    enableWebhook: false
NVIPAM
fi
}
function nodeFeatureDiscovery()
{
  if [ "${NFD_ENABLE}" != true ];then
     return
  fi
cat << NODE_FEATURE_DISCOVERY
  nodeFeatureDiscovery:
    image: node-feature-discovery
    repository:  $(get_repository node-feature-discovery required)
    version:  $(get_release_tag node-feature-discovery)
NODE_FEATURE_DISCOVERY
}
function nicFeatureDiscovery()
{
  if [ "${NIC_FD_ENABLE}" != true ];then
    return
  fi
  REPOSITORY=$(get_repository nic-feature-discovery optional)
  if [ "${REPOSITORY}" = "" ];then
    return
  fi
cat << NIC_FEATURE_DISCOVERY
  nicFeatureDiscovery:
    image: nic-feature-discovery
    repository: ${REPOSITORY}
    version: $(get_release_tag nic-feature-discovery)
NIC_FEATURE_DISCOVERY
}
function nicConfigurationOperator()
{
if [ "${NIC_CONFIG_ENABLE}" != true ];then
  return
fi
REPOSITORY=$(get_repository nic-configuration-operator optional)
if [ "${REPOSITORY}" = "" ];then
  return
fi
cat << NIC_CONFIGURATION
  nicConfigurationOperator:
    operator:
      image: nic-configuration-operator
      repository: ${REPOSITORY}
      version: $(get_release_tag nic-configuration-operator)
    configurationDaemon:
      image: nic-configuration-operator-daemon
      repository: $(get_repository nic-configuration-operator-daemon required)
      version: $(get_release_tag nic-configuration-operator-daemon)
    nicFirmwareStorage:
      create: false
      pvcName: nic-fw-storage-pvc
      # Name of the storage class is provided by the user
      storageClassName: nfs-csi
      availableStorageSize: 1Gi
NIC_CONFIGURATION
}
function maintenanceOperator()
{
if [ "${MAINTENANCE_OPERATOR_ENABLE}" != true ];then
  return
fi
REPOSITORY=$(get_repository maintenance-operator optional)
if [ "${REPOSITORY}" = "" ];then
  return
fi
cat << MAINTENANCE_OPERATOR
  maintenanceOperator:
    image: maintenance-operator
    repository: ${REPOSITORY}
    version: $(get_release_tag maintenance-operator)
MAINTENANCE_OPERATOR
}
function mk_file()
{
init_file "${FILE}"
cat << HEREDOC1 >> ${FILE}
---
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: nic-cluster-policy
spec:
HEREDOC1
ofedDriver >> ${FILE}
case ${USECASE} in
ipoib_rdma_shared_device)
  #LINK_TYPES='"IB"' breaks plugin
  LINK_TYPES=""
  rdmaSharedDevicePlugin >> ${FILE}
  ;;
macvlan_rdma_shared_device)
  LINK_TYPES='"ether"'
  rdmaSharedDevicePlugin >> ${FILE}
  ;;
hostdev_rdma_sriov)
  sriovDevicePlugin >> ${FILE}
  ;;
esac
secondaryNetwork >> ${FILE}
nvIpam >> ${FILE}
nodeFeatureDiscovery >> ${FILE}
nicFeatureDiscovery >> ${FILE}
nicConfigurationOperator >> ${FILE}
maintenanceOperator >> ${FILE}
}
NETOP_JINGA_CONFIG=false
FILE="${NETOP_NICCLUSTER_FILE}"
mk_file
if [ "${NETOP_BCM_CONFIG}" == true ];then
   NETOP_JINGA_CONFIG=true
   FILE="${NETOP_NICCLUSTER_FILE}.j2"
   mk_file
fi
