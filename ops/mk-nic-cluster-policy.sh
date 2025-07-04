#!/bin/bash -x
#
# nic cluster plocy file has migrated outof the values.yaml file
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
case ${NETOP_VERSION} in
24.7.0)
  DOCA_VERSION="24.07-0.6.1.0-0"
  MULTUS_VERSION="v3.9.3"
  RDMA_SDP_VERSION="v1.5.1"
  SRIOV_DP_VERSION="v3.7.0"
  ;;&
24.10.0 | 24.10.1)
  DOCA_VERSION="24.10-0.7.0.0-0"
  MULTUS_VERSION="v4.1.0"
  RDMA_SDP_VERSION="v1.5.2"
  SRIOV_DP_VERSION="v3.8.0"
  IPOIB_VERSION="v1.2.0"
  NIC_FEATURE_VERSION="v0.0.1"
  MAINTENANCE_OPERATOR_VERSION="v0.2.0"
  ;;&
25.1.0)
  DOCA_VERSION="25.01-0.6.0.0-0"
  RDMA_SDP_VERSION="v1.5.2"
  SRIOV_DP_VERSION="v3.9.0"
  MULTUS_VERSION="v4.1.0"
  IPOIB_VERSION="v1.2.1"
  NIC_FEATURE_VERSION="v0.0.1"
  MAINTENANCE_OPERATOR_VERSION="v0.2.0"
  ;;&
25.4.0)
  NETWORK_OPERATOR_CONTAINER="v0.0.3"
  DOCA_VERSION="25.04-0.6.1.0-2"
  RDMA_SDP_VERSION="v1.5.3"
  IB_KUBERNETES_VERSION="v1.1.1"
  IPOIB_VERSION="v1.2.2"
  NVIPAM_VERSION="v0.3.7"
  DOCA_TELEMETRY_SERVICE_VERSION="1.16.5-doca2.6.0-host"
  NODE_FEATURE_DISCOVERY_VERSION="v0.15.6"
  SRIOV_DP_VERSION="v3.9.0"
  MULTUS_VERSION="v4.1.0"
  NIC_FEATURE_VERSION="v0.0.2"
  NIC_CONFIGURATIOMN_OPERATOR_VERSION="v1.0.3"
  OVS_CNI_VERSION="v0.38.2"
  MAINTENANCE_OPERATOR_VERSION="v0.2.0"
  ;;&
*)
  DOCA_VERSION=${DOCA_VERSION:-"24.10-0.7.0.0-0"}
  IPOIB_VERSION=${IPOIB_VERSION:-"428715a57c0b633e48ec7620f6e3af6863149ccf"}
  CNI_PLUGINS_VERSION=${CNI_PLUGINS_VERSION:-"v1.5.0"}
  WHEREABOUTS_VERSION=${WHEREABOUTS_VERSION:-"v0.7.0"}
  NVIPAM_VERSION=${NVIPAM_VERSION:-"v0.2.0"}
  IB_KUBERNETES_VERSION=${IB_KUBERNETES:-"v1.1.0"}
  #NODE_FEATURE_VERSION=${NODE_FEATURE_VERSION:-"v0.15.6"}
  ;;
esac
function ofedDriver()
{
if [ ${OFED_ENABLE} = false ];then
  return
fi
cat << OFED_DRIVER0
  ofedDriver:
    image: doca-driver
    repository: nvcr.io/nvidia/mellanox
    version: ${DOCA_VERSION}
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
OFED_DRIVER0
    #
    # should be fixed in 25.4.0
    #
    if [ "${OFED_BLACKLIST_ENABLE}" = "true" ];then
cat << OFED_DRIVER1
    - name: OFED_BLACKLIST_MODULES_FILE
      value: "/host/etc/modprobe.d/blacklist-ofed-modules.conf"
OFED_DRIVER1
    fi
    if [ "${OFED_BLACKLIST_ADD}" != "" ];then
cat << OFED_DRIVER2
    - name:  OFED_BLACKLIST_MODULES
      value: "mlx5_core:mlx5_ib:ib_umad:ib_uverbs:ib_ipoib:rdma_cm:rdma_ucm:ib_core:ib_cm:${OFED_BLACKLIST_ADD}"
OFED_DRIVER2
    fi
cat << OFED_DRIVER3
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
OFED_DRIVER3
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
    repository: ghcr.io/mellanox
    version: ${RDMA_SDP_VERSION}
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
      repository: ghcr.io/k8snetworkplumbingwg
      version: ${CNI_PLUGINS_VERSION}
      imagePullSecrets: []
    multus:
      image: multus-cni
      repository: ghcr.io/k8snetworkplumbingwg
      version: ${MULTUS_VERSION}
      imagePullSecrets: []
SECONDARY_NETWORK1
if [ "${NETOP_NETWORK_TYPE}" = "IPoIBNetwork" ];then
cat << SECONDARY_NETWORK2
    ipoib:
      image: ipoib-cni
      repository: ghcr.io/mellanox
      version: ${IPOIB_VERSION}
      imagePullSecrets: []
SECONDARY_NETWORK2
fi
if [ "${IPAM_TYPE}" = "whereabouts" ];then
cat << SECONDARY_NETWORK3 >> ${FILE}
    ipamPlugin:
      image: whereabouts
      repository: ghcr.io/k8snetworkplumbingwg
      version: ${WHEREABOUTS_VERSION}
      imagePullSecrets: []
SECONDARY_NETWORK3
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
function nicFeatureDiscovery()
{
  if [ "${NIC_FEATURE_VERSION}" != "" ];then
cat << NIC_FEATURE_DISCOVERY
  nicFeatureDiscovery:
    image: nic-feature-discovery
    repository: ghcr.io/mellanox
    version: ${NIC_FEATURE_VERSION}
NIC_FEATURE_DISCOVERY
  fi
}
function nodeFeatureDiscovery()
{
  if [ "${NODE_FEATURE_VERSION}" != "" ];then
cat << NODE_FEATURE_DISCOVERY
  nodeFeatureDiscovery:
    image: node-feature-discovery
    repository: registry.k8s.io/nfd
    version: ${NODE_FEATURE_VERSION}
NODE_FEATURE_DISCOVERY
  fi
}
function maintenanceOperator()
{
  if [ "${MAINTENANCE_OPERATOR_VERSION}" != "" ];then
cat << MAINTENANCE_OPERATOR
  nodeFeatureDiscovery:
    image: maintenance-operator
    repository: ghcr.io/mellanox
    version: ${MAINTENANCE_OPERATOR_VERSION}
MAINTENANCE_OPERATOR
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
if [ ${NIC_CONFIG_ENABLE} == "true" ];then
  nicFeatureDiscovery >> ${FILE}
fi
