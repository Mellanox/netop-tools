#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
NFD_ENABLE=${NFD_ENABLE:-true}
NIC_CONFIG_ENABLE=${NIC_CONFIG_ENABLE:-true}

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
  REPOSITORY=$(netop_resolve_repository "${REPOSITORY}")
  echo ${REPOSITORY}
}
function get_release_tag()
{
  LINE=$(get_container ${1})
  echo "${LINE}" | cut -d, -f5
}
function get_mod_tag()
{
  LINE=$(get_container ${1})
  echo "${LINE}" | cut -d, -f6
}
function get_image_uri()
{
  CONTAINER="${1}"
  REPOSITORY=$(get_repository "${CONTAINER}")
  RELEASE_TAG=$(get_release_tag "${CONTAINER}")
  MOD_TAG=$(get_mod_tag "${CONTAINER}")
  if [ -n "${REPOSITORY}" ] && [ -n "${RELEASE_TAG}" ];then
    echo "${REPOSITORY}/${CONTAINER}:${RELEASE_TAG}${MOD_TAG}"
  fi
}
function emit_image_uri()
{
  local KEY="${1}"
  local CONTAINER="${2}"
  local IMAGE_URI
  IMAGE_URI=$(get_image_uri "${CONTAINER}")
  if [ -n "${IMAGE_URI}" ];then
    echo "    ${KEY}: ${IMAGE_URI}"
  fi
}
function operatorImages()
{
if [ -z "${NETOP_REGISTRY}" ];then
  return
fi
OPERATOR_REPOSITORY=$(get_repository network-operator)
OPERATOR_TAG=$(get_release_tag network-operator)
if [ -z "${OPERATOR_REPOSITORY}" ] || [ -z "${OPERATOR_TAG}" ];then
  return
fi
OPERATOR_INIT_REPOSITORY=$(get_repository network-operator-init-container)
OPERATOR_INIT_TAG=$(get_release_tag network-operator-init-container)
cat << OPERATOR_IMAGES
operator:
  repository: ${OPERATOR_REPOSITORY}
  image: network-operator
  tag: ${OPERATOR_TAG}
OPERATOR_IMAGES
if [ -n "${OPERATOR_INIT_REPOSITORY}" ] && [ -n "${OPERATOR_INIT_TAG}" ];then
case ${NETOP_VERSION} in
  24.7.*)
    ;;
  *)
cat << OPERATOR_INIT_IMAGE
  ofedDriver:
    initContainer:
      repository: ${OPERATOR_INIT_REPOSITORY}
      image: network-operator-init-container
      version: ${OPERATOR_INIT_TAG}
OPERATOR_INIT_IMAGE
    ;;
esac
fi
}

function sriovNetworkOperator()
{
case ${USECASE} in
sriovnet_rdma|sriovnet_dra)
  SRIOVNET="true"
  IPOIBVAL="false"
  ;;
sriovibnet_rdma)
  SRIOVNET="true"
  IPOIBVAL="false"
  ;;
*)
  SRIOVNET="false"
  return
esac
cat << SRIOV_NETWORK_OPERATOR0
sriovNetworkOperator:
  enabled: ${SRIOVNET}
sriov-network-operator:
  sriovOperatorConfig:
    configDaemonNodeSelector:
      ${NETOP_NODESELECTOR}: "${NETOP_NODESELECTOR_VAL}"
SRIOV_NETWORK_OPERATOR0

if [ "${NIC_CONFIG_ENABLE}" = "true" ];then
  case ${NETOP_VERSION} in
    25.10.*|26.1.*|26.4.*)
cat << SRIOV_NETWORK_OPERATOR0
      network.nvidia.com/operator.mofed.wait: "false"
      # Enable when using together with NIC Configuration Operator to wait until
      # all required FW parameters are successfully applied before configuring SR-IOV
      network.nvidia.com/operator.nic-configuration.wait: "true"
SRIOV_NETWORK_OPERATOR0
      ;;
    *)
      ;;
  esac
fi

cat << SRIOV_NETWORK_OPERATOR0
    featureGates:
      parallelNicConfig: ${FG_PARALLEL_NIC_CONFIG}
      mellanoxFirmwareReset: ${FG_MLNX_FW_RESET}
SRIOV_NETWORK_OPERATOR0
if [ "${DRA_ENABLE}" = "true" ];then
  case ${NETOP_VERSION} in
    26.4.*)
cat << SRIOV_DRA_FG
      dynamicResourceAllocation: true
SRIOV_DRA_FG
      ;;
  esac
fi
if [ "${NETOP_BCM_CONFIG}" == false ];then
cat << SRIOV_NETWORK_OPERATOR1
      resourceInjectorMatchCondition: ${FG_RESOURCE_INJECTOR_MATCH}
      metricsExporter: ${METRICS_EXPORTER}
      manageSoftwareBridges: ${MANAGE_SW_BRIDGE}
SRIOV_NETWORK_OPERATOR1
fi
if [ -n "${NETOP_REGISTRY}" ];then
cat << SRIOV_IMAGES
  images:
SRIOV_IMAGES
  emit_image_uri operator sriov-network-operator
  emit_image_uri sriovConfigDaemon sriov-network-operator-config-daemon
  emit_image_uri sriovCni sriov-cni
  emit_image_uri ibSriovCni ib-sriov-cni
  emit_image_uri ovsCni ovs-cni-plugin
  emit_image_uri rdmaCni rdma-cni
  emit_image_uri sriovDevicePlugin sriov-network-device-plugin
  emit_image_uri sriovDraDriver dra-driver-sriov
  RESOURCES_INJECTOR_IMAGE=$(get_image_uri network-resources-injector)
  if [ -z "${RESOURCES_INJECTOR_IMAGE}" ];then
    RESOURCES_INJECTOR_IMAGE=$(netop_resolve_image_uri ghcr.io/k8snetworkplumbingwg/network-resources-injector)
  fi
  echo "    resourcesInjector: ${RESOURCES_INJECTOR_IMAGE}"
  emit_image_uri webhook sriov-network-operator-webhook
  case ${NETOP_VERSION} in
    26.4.*)
cat << SRIOV_IMAGES_METRICS
    metricsExporter: $(netop_resolve_image_uri ghcr.io/k8snetworkplumbingwg/sriov-network-metrics-exporter)
    metricsExporterKubeRbacProxy: $(netop_resolve_image_uri quay.io/brancz/kube-rbac-proxy:v0.21.2)
SRIOV_IMAGES_METRICS
      ;;
  esac
fi
if [ "${DRA_ENABLE}" = "true" ];then
  case ${NETOP_VERSION} in
    26.4.*)
      if [ -z "${NETOP_REGISTRY}" ];then
cat << SRIOV_DRA
  images:
    sriovDraDriver: $(get_repository dra-driver-sriov)/dra-driver-sriov:$(get_release_tag dra-driver-sriov)
draDriver:
  cdiRoot: "${DRA_CDI_ROOT}"
  defaultInterfacePrefix: "${DRA_IFACE_PREFIX}"
SRIOV_DRA
      else
cat << SRIOV_DRA
draDriver:
  cdiRoot: "${DRA_CDI_ROOT}"
  defaultInterfacePrefix: "${DRA_IFACE_PREFIX}"
SRIOV_DRA
      fi
      ;;
  esac
fi
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
NFD_PULL_SECRET="false"
MAINT_PULL_SECRET="false"
#NodeFeatureRule: ${NFD_ENABLE}
cat <<VALUES_YAML0
nfd:
  enabled: ${NFD_ENABLE}
VALUES_YAML0
case "${NETOP_VERSION}" in
25.4.0|25.7.0|25.10.*|26.1.*|26.4.*)
cat << VALUES_YAML1
  deployNodeFeatureRules: ${NFD_ENABLE}
VALUES_YAML1
  ;;
*)
  ;;
esac
if [ "${NFD_ENABLE}" = "true" ] && [ "${PROD_VER}" = "0" ]; then
  case "${NETOP_VERSION}" in
  26.4.*)
    NFD_PULL_SECRET="true"
    ;;
  esac
fi
if [ -n "${NETOP_REGISTRY}" ] || [ "${NFD_PULL_SECRET}" = "true" ];then
cat << VALUES_NFD_PULL
node-feature-discovery:
VALUES_NFD_PULL
  if [ -n "${NETOP_REGISTRY}" ];then
cat << VALUES_NFD_IMAGE
  image:
    repository: $(get_repository node-feature-discovery)/node-feature-discovery
    tag: $(get_release_tag node-feature-discovery)
VALUES_NFD_IMAGE
  fi
  if [ "${NFD_PULL_SECRET}" = "true" ];then
cat << VALUES_NFD_PULL_SECRET
  imagePullSecrets:
    - name: ${NGC_SECRET:-ngc-image-secret}
VALUES_NFD_PULL_SECRET
  fi
fi

case "${NETOP_VERSION}" in
  25.1.0)
    param=nicConfigurationOperator
    param_val="${NIC_CONFIG_ENABLE}"
    ;;
  *)
    param=maintenanceOperator
    param_val="${MAINTENANCE_OPERATOR_ENABLE}"
    ;;
esac

cat << VALUES_YAML2
${param}:
  enabled: ${param_val}
nvIpam:
  deploy: ${NVIPAMVAL}
VALUES_YAML2
if [ "${MAINTENANCE_OPERATOR_ENABLE}" = "true" ] && [ "${PROD_VER}" = "0" ]; then
  case "${NETOP_VERSION}" in
  26.4.*)
    MAINT_PULL_SECRET="true"
    ;;
  esac
fi
MAINT_REPOSITORY=""
MAINT_TAG=""
if [ -n "${NETOP_REGISTRY}" ];then
  MAINT_REPOSITORY=$(get_repository maintenance-operator)
  MAINT_TAG=$(get_release_tag maintenance-operator)
fi
if [ -n "${MAINT_REPOSITORY}" ] || [ "${MAINT_PULL_SECRET}" = "true" ];then
cat << VALUES_MAINT_PULL
maintenance-operator-chart:
VALUES_MAINT_PULL
  if [ -n "${MAINT_REPOSITORY}" ];then
cat << VALUES_MAINT_IMAGE
  operator:
    image:
      repository: ${MAINT_REPOSITORY}
      name: maintenance-operator
      tag: ${MAINT_TAG}
VALUES_MAINT_IMAGE
  fi
  if [ "${MAINT_PULL_SECRET}" = "true" ];then
cat << VALUES_MAINT_PULL_SECRET
  imagePullSecrets:
    - name: ${NGC_SECRET:-ngc-image-secret}
VALUES_MAINT_PULL_SECRET
  fi
fi
}
function deployCR()
{
cat <<DEPLOY_CR_YAML1
# NicClusterPolicy CR values
deployCR: ${1}
DEPLOY_CR_YAML1
}
function ofedDriver()
{
if [ -z "${NETOP_REGISTRY}" ];then
  return
fi
OPERATOR_INIT_REPOSITORY=$(get_repository network-operator-init-container)
OPERATOR_INIT_TAG=$(get_release_tag network-operator-init-container)
if [ -z "${OPERATOR_INIT_REPOSITORY}" ] || [ -z "${OPERATOR_INIT_TAG}" ];then
  return
fi
cat << OFED_DRIVER
ofedDriver:
  initContainer:
    repository: ${OPERATOR_INIT_REPOSITORY}
    image: network-operator-init-container
    version: ${OPERATOR_INIT_TAG}
OFED_DRIVER
}
function rdmaSharedDevicePlugin()
{
case ${USECASE} in
ipoib_rdma_shared_device|macvlan_rdma_shared_device)
cat << RDMA_SDP1
rdmaSharedDevicePlugin:
  deploy: true
  resources:
RDMA_SDP1
  ;;
*)
cat << RDMA_SDP2
rdmaSharedDevicePlugin:
  deploy: false
RDMA_SDP2
  return
  ;;
esac
for DEVDEF in ${NETOP_NETLIST[@]};do
  IFS=',' read NIDX DEVICEID NETOP_HCAMAX DEVNAMES <<< ${DEVDEF}
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
echo "      linkTypes: [${LINK_TYPES}]"
    fi
  fi
done
}
function sriovDevicePlugin()
{
case ${USECASE} in
hostdev_rdma_sriov)
cat << SRIOV_DP1
sriovDevicePlugin:
  deploy: true
  resources:
SRIOV_DP1
  ;;
*)
cat << SRIOV_DP2
sriovDevicePlugin:
  deploy: false
SRIOV_DP2
  return
  ;;
esac
for DEVDEF in ${NETOP_NETLIST[@]};do
  IFS=',' read NIDX DEVICEID NETOP_HCAMAX DEVNAMES <<< ${DEVDEF}
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
#  ipoib:
#    deploy: ${IPOIBVAL}
}
function version()
{
  if [ "${NETOP_TAG_VERSION}" == true ];then
    echo "# VERSION:${NETOP_VERSION}"
  fi
  echo "---"
}
function 24_7_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  deployCR false
  sriovNetworkOperator
  pullSecrets
  ofedDriver
}
function 24_10_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  deployCR true
  sriovNetworkOperator
  pullSecrets
# ofedDriver
}
function 24_10_1()
{
  version
  ipamType
  values_yaml
  operatorImages
  deployCR true
  sriovNetworkOperator
  pullSecrets
}
function 25_1_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  deployCR false
  sriovNetworkOperator
  pullSecrets
  secondaryNetwork
}
function 25_4_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  sriovNetworkOperator
  pullSecrets
}
function 25_7_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  sriovNetworkOperator
  pullSecrets
}
function 25_10_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  sriovNetworkOperator
  pullSecrets
}
function 26_1_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  sriovNetworkOperator
  pullSecrets
}
function 26_4_0()
{
  version
  ipamType
  values_yaml
  operatorImages
  sriovNetworkOperator
  pullSecrets
}

case ${NETOP_VERSION} in
  26.4.*)
    NETOP_FUNCT=26_4_0
    ;;
  26.1.*)
    NETOP_FUNCT=26_1_0
    ;;
  25.10.*)
    NETOP_FUNCT=25_10_0
    ;;
  25.7.0)
    NETOP_FUNCT=25_7_0
    ;;
  25.4.0)
    NETOP_FUNCT=25_4_0
    ;;
  25.1.0)
    NETOP_FUNCT=25_1_0
    ;;
  24.10.0|24.10.1)
    NETOP_FUNCT=24_10_1
    ;;
  24.7.0|24.1.1)
    NETOP_FUNCT=24_7_0
    ;;
  *)
    echo "Cannot detect function to execute for ${NETOP_VERSION}"
    exit 1
    ;;
esac

${NETOP_FUNCT} > ${NETOP_VALUES_FILE}
