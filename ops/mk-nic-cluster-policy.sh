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
    echo "ERROR: required repository ${1} not found in container list ${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}" >&2
    return 1
  fi
  REPOSITORY=$(netop_resolve_repository "${REPOSITORY}")
  echo ${REPOSITORY}
}
function get_release_tag()
{
  LINE=$(get_container ${1})
  echo "${LINE}" | cut -d, -f5
}
function require_container()
{
  local CONTAINER="${1}"
  local LINE
  local REPOSITORY
  local RELEASE_TAG

  LINE=$(get_container "${CONTAINER}")
  REPOSITORY=$(echo "${LINE}" | cut -d, -f3)
  RELEASE_TAG=$(echo "${LINE}" | cut -d, -f5)
  if [ -z "${REPOSITORY}" ] || [ -z "${RELEASE_TAG}" ];then
    echo "ERROR: required container ${CONTAINER} missing repository or version in ${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}" >&2
    return 1
  fi
}
function validate_required_containers()
{
  local REQUIRED_CONTAINERS=(plugins multus-cni)
  local CONTAINER
  local MISSING=0

  if [ "${IPAM_TYPE}" = "nv-ipam" ];then
    REQUIRED_CONTAINERS+=(nvidia-k8s-ipam)
  fi
  if [ "${IPAM_TYPE}" = "whereabouts" ];then
    REQUIRED_CONTAINERS+=(whereabouts)
  fi
  if [ "${NETOP_NETWORK_TYPE}" = "IPoIBNetwork" ];then
    REQUIRED_CONTAINERS+=(ipoib-cni)
  fi
  if [ ${#NETOP_NODEPOOLS[@]} -eq 0 ] && [ "${NIC_NODE_POLICY_ENABLE}" != "true" ]; then
    if [ "${OFED_ENABLE}" = true ];then
      REQUIRED_CONTAINERS+=(doca-driver)
    fi
    case ${USECASE} in
    ipoib_rdma_shared_device|macvlan_rdma_shared_device)
      REQUIRED_CONTAINERS+=(k8s-rdma-shared-dev-plugin)
      ;;
    hostdev_rdma_sriov)
      REQUIRED_CONTAINERS+=(sriov-network-device-plugin)
      ;;
    esac
  fi
  case ${NETOP_VERSION} in
    26.4.*)
      if [ "${NCP_GLOBAL_CONFIG}" = "true" ];then
        REQUIRED_CONTAINERS+=(network-operator-init-container)
      fi
      ;;
  esac
  if [ "${NIC_CONFIG_ENABLE}" = true ] && [ -n "$(get_container nic-configuration-operator)" ];then
    REQUIRED_CONTAINERS+=(nic-configuration-operator nic-configuration-operator-daemon)
  fi

  for CONTAINER in "${REQUIRED_CONTAINERS[@]}";do
    require_container "${CONTAINER}" || MISSING=1
  done
  if [ "${MISSING}" = "1" ];then
    exit 1
  fi
}
function globalConfig()
{
case ${NETOP_VERSION} in
  26.4.*)
    ;;
  *)
    return
    ;;
esac
if [ "${NCP_GLOBAL_CONFIG}" != "true" ];then
  return
fi
# Default repo/version from network-operator-init-container, which shares the
# same registry and tag as all other core network-operator components.
GLOBAL_REPO=${NCP_GLOBAL_REPO:-$(get_repository network-operator-init-container required)}
GLOBAL_VER=${NCP_GLOBAL_VER:-$(get_release_tag network-operator-init-container)}
cat << GLOBAL_CONFIG
  global:
    repository: ${GLOBAL_REPO}
    version: ${GLOBAL_VER}
    imagePullSecrets: [${NGC_SECRET}]
GLOBAL_CONFIG
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
    imagePullSecrets: [${NGC_SECRET}]
    terminationGracePeriodSeconds: 300
    env:
    - name: RESTORE_DRIVER_ON_POD_TERMINATION
      value: "true"
    - name: UNLOAD_STORAGE_MODULES
      value: "true"
    - name: CREATE_IFNAMES_UDEV
      value: "true"
OFED_DRIVER3
    if [ "${ENTRYPOINT_DEBUG}" = "true" ];then
cat << OFED_DRIVER8
    - name: ENTRYPOINT_DEBUG
      value: "true"
    - name: DEBUG_LOG_FILE
      value: "${DEBUG_LOG_FILE}"
    - name: DEBUG_SLEEP_SEC_ON_EXIT
      value: "${DEBUG_SLEEP_SEC_ON_EXIT}"
OFED_DRIVER8
    fi
    #
    # should be fixed in 25.4.0
    #
    if [ "${OFED_BLACKLIST_ENABLE}" = "true" ];then
cat << OFED_DRIVER4
    - name: OFED_BLACKLIST_MODULES_FILE
      value: "${OFED_BLACKLIST_MODULES_FILE}"
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
    if [ "${UNLOAD_THIRD_PARTY_RDMA}" = "true" ];then
      case ${NETOP_VERSION} in
        26.4.*)
cat << OFED_DRIVER9
    - name: UNLOAD_THIRD_PARTY_RDMA_MODULES
      value: "true"
OFED_DRIVER9
          ;;
      esac
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
    imagePullSecrets: [${NGC_SECRET}]
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
    imagePullSecrets: [${NGC_SECRET}]
    # The config below directly propagates to k8s-rdma-shared-device-plugin configuration.
    # Replace 'devices' with your (RDMA capable) netdevice name.
    config: |
      {
        "configList": [
RDMA_SDP1
NETWORKS=${#NETOP_NETLIST[@]}
COMMA=","
for DEVDEF in ${NETOP_NETLIST[@]};do
  IFS=',' read NIDX DEVICEID HCAMAX DEVNAMES <<< ${DEVDEF}
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
  let NETWORKS=NETWORKS-1
  if [ ${NETWORKS} -le 0 ];then
    COMMA=""
  fi
  HCAMAX=${HCAMAX:=${NETOP_HCAMAX}}
#           "resourcePrefix": "nvidia.com",
cat << RDMA_SDP2
          {
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "rdmaHcaMax": ${HCAMAX},
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
function ibKubernetes()
{
if [ "${IB_KUBERNETES_ENABLE}" != "true" ];then
  return
fi
REPOSITORY=$(get_repository ib-kubernetes optional)
if [ "${REPOSITORY}" = "" ];then
  return
fi
cat << IB_KUBERNETES
  ibKubernetes:
    image: ib-kubernetes
    repository: ${REPOSITORY}
    version: $(get_release_tag ib-kubernetes)
    imagePullSecrets: [${NGC_SECRET}]
    pKeyGUIDPoolRangeStart: "${IB_GUID_RANGE_START}"
    pKeyGUIDPoolRangeEnd: "${IB_GUID_RANGE_END}"
    ufmSecret: ${IB_UFM_SECRET}
IB_KUBERNETES
}
function secondaryNetwork()
{
cat << SECONDARY_NETWORK1
  secondaryNetwork:
    cniPlugins:
      image: plugins
      repository: $(get_repository plugins required)
      version: $(get_release_tag plugins)
      imagePullSecrets: [${NGC_SECRET}]
    multus:
      image: multus-cni
      repository: $(get_repository multus-cni required)
      version: $(get_release_tag multus-cni)
      imagePullSecrets: [${NGC_SECRET}]
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
      imagePullSecrets: [${NGC_SECRET}]
SECONDARY_NETWORK3
    ;;
esac
if [ "${IPAM_TYPE}" = "whereabouts" ];then
cat << SECONDARY_NETWORK4
    ipamPlugin:
      image: whereabouts
      repository: $(get_repository whereabouts required)
      version: $(get_release_tag whereabouts)
      imagePullSecrets: [${NGC_SECRET}]
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
    imagePullSecrets: [${NGC_SECRET}]
    enableWebhook: false
NVIPAM
fi
}
function nodeFeatureDiscovery()
{
#TODO
#Leaving it here for future use. Probably can be consolidated with generation of values.yaml
  return
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
NIC_CONFIGURATION

if [ "${FW_UPGRADE_ENABLE}" = "true" ];then
  case "${NETOP_VERSION}" in
    25.4.0|25.7.0|25.10.*|26.1.*|26.4.*)
cat << NIC_CONFIGURATION
    nicFirmwareStorage:
      create: ${NETOP_BCM_CONFIG}
      pvcName: nic-fw-storage-pvc
      # Name of the storage class is provided by the user
      storageClassName: nfs-csi
      availableStorageSize: 1Gi
NIC_CONFIGURATION
;;
*)
;;
esac
fi
}
function spectrumXOperator()
{
if [ "${SPECTRUM_X_ENABLE}" != "true" ];then
  return
fi
case ${NETOP_VERSION} in
  26.4.*)
    ;;
  *)
    return
    ;;
esac
REPOSITORY=$(get_repository spectrum-x-operator optional)
if [ "${REPOSITORY}" = "" ];then
  return
fi
cat << SPECTRUMX
  spectrumXOperator:
    image: spectrum-x-operator
    repository: ${REPOSITORY}
    version: $(get_release_tag spectrum-x-operator)
    imagePullSecrets: [${NGC_SECRET}]
SPECTRUMX
XPLANE_REPO=$(get_repository xplane optional)
if [ "${XPLANE_REPO}" != "" ];then
cat << SPECTRUMX_XPLANE
    xPlane:
      image: xplane
      repository: ${XPLANE_REPO}
      version: $(get_release_tag xplane)
      imagePullSecrets: [${NGC_SECRET}]
SPECTRUMX_XPLANE
fi
}
function maintenanceOperator()
{
  # maintenanceOperator is now defined in the Helm chart values, not in
  # NicClusterPolicy. This function is intentionally empty.
  return
}
function docaTelemetryService()
{
if [ "${DOCA_TELEMETRY_SERVICE}" != "true" ];then
  return
fi
REPOSITORY=$(get_repository doca_telemetry)
if [ "${REPOSITORY}" = "" ];then
  return
fi
cat << DOCA_TELEMETRY
  docaTelemetryService:
    image: doca_telemetry
    imagePullSecrets: [${NGC_SECRET}]
    repository: ${REPOSITORY}
    version: $(get_release_tag doca_telemetry)
DOCA_TELEMETRY
}
function node_affinity()
{
if [ "${NCP_NODE_AFFINITY}" == "true" ];then
cat << NODE_AFFINITY
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: feature.node.kubernetes.io/pci-15b3.present
          operator: In
          values:
          - "true"
NODE_AFFINITY
fi
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
globalConfig >> ${FILE}
docaTelemetryService >> ${FILE}
node_affinity >> ${FILE}
if [ ${#NETOP_NODEPOOLS[@]} -eq 0 ] && [ "${NIC_NODE_POLICY_ENABLE}" != "true" ]; then
  ofedDriver >> ${FILE}
fi
ibKubernetes >> ${FILE}
if [ ${#NETOP_NODEPOOLS[@]} -eq 0 ] && [ "${NIC_NODE_POLICY_ENABLE}" != "true" ]; then
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
fi
secondaryNetwork >> ${FILE}
nvIpam >> ${FILE}
nodeFeatureDiscovery >> ${FILE}
nicFeatureDiscovery >> ${FILE}
nicConfigurationOperator >> ${FILE}
spectrumXOperator >> ${FILE}
maintenanceOperator >> ${FILE}
}
NETOP_JINGA_CONFIG=false
FILE="${NETOP_NICCLUSTER_FILE}"
validate_required_containers
mk_file
if [ "${NETOP_BCM_CONFIG}" == true ];then
   NETOP_JINGA_CONFIG=true
   FILE="${NETOP_NICCLUSTER_FILE}.j2"
   mk_file
fi
