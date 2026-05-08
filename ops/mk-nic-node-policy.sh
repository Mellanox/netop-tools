#!/bin/bash
#
# Generate NicNodePolicy CR — per-node-group OFED driver and device plugin config.
# NicNodePolicy is a sibling to NicClusterPolicy that targets a specific node subset
# via nodeSelector. Supported from 26.4.0+.
# For sriovnet_rdma/sriovibnet_rdma use cases, only ofedDriver is emitted here;
# the SR-IOV device plugin is managed by the SR-IOV network operator.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

case ${NETOP_VERSION} in
  26.4.*)
    ;;
  *)
    echo "ERROR: NicNodePolicy requires NETOP_VERSION 26.4.x or later (current: ${NETOP_VERSION})"
    exit 1
    ;;
esac

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
  if [ "${2}" = "required" ] && [ "${REPOSITORY}" = "" ];then
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

function init_file()
{
  if [ "${NETOP_TAG_VERSION}" == true ];then
    echo "# VERSION:${NETOP_VERSION}" > "${1}"
  else
    rm -f "${1}"
  fi
}

FILE="${NIC_NODE_POLICY_FILE}"
init_file "${FILE}"

NIC_NODE_POLICY_NAME="nic-node-policy${NETOP_ACTIVE_POOL:+-${NETOP_ACTIVE_POOL,,}}"

cat << HEREDOC >> ${FILE}
---
apiVersion: mellanox.com/v1alpha1
kind: NicNodePolicy
metadata:
  name: ${NIC_NODE_POLICY_NAME}
spec:
  nodeSelector:
    ${NETOP_NODESELECTOR}: "${NETOP_NODESELECTOR_VAL}"
  ofedDriver:
    image: doca-driver
    repository: $(get_repository doca-driver required)
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
HEREDOC

if [ "${UNLOAD_THIRD_PARTY_RDMA}" = "true" ];then
cat << HEREDOC >> ${FILE}
    - name: UNLOAD_THIRD_PARTY_RDMA_MODULES
      value: "true"
HEREDOC
fi

cat << HEREDOC >> ${FILE}
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
HEREDOC

case ${USECASE} in
sriovnet_rdma|sriovibnet_rdma)
  # SR-IOV device plugin is managed by the SR-IOV network operator; NicNodePolicy
  # only needs to configure ofedDriver for these use cases.
  ;;
ipoib_rdma_shared_device)
  LINK_TYPES=""
cat << HEREDOC >> ${FILE}
  rdmaSharedDevicePlugin:
    image: k8s-rdma-shared-dev-plugin
    repository: $(get_repository k8s-rdma-shared-dev-plugin required)
    version: $(get_release_tag k8s-rdma-shared-dev-plugin)
    imagePullSecrets: [${NGC_SECRET}]
    config: |
      {
        "configList": [
HEREDOC
  NETWORKS=${#NETOP_NETLIST[@]}
  COMMA=","
  for DEVDEF in ${NETOP_NETLIST[@]};do
    IFS=',' read NIDX DEVICEID HCAMAX DEVNAMES <<< ${DEVDEF}
    DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
    let NETWORKS=NETWORKS-1
    [ ${NETWORKS} -le 0 ] && COMMA=""
    HCAMAX=${HCAMAX:=${NETOP_HCAMAX}}
cat << HEREDOC >> ${FILE}
          {
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "rdmaHcaMax": ${HCAMAX},
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              "ifNames": ["${DEVNAMES}"],
              "isRdma": true
            }
          }${COMMA}
HEREDOC
  done
cat << HEREDOC >> ${FILE}
        ]
      }
HEREDOC
  ;;
macvlan_rdma_shared_device)
  LINK_TYPES='"ether"'
cat << HEREDOC >> ${FILE}
  rdmaSharedDevicePlugin:
    image: k8s-rdma-shared-dev-plugin
    repository: $(get_repository k8s-rdma-shared-dev-plugin required)
    version: $(get_release_tag k8s-rdma-shared-dev-plugin)
    imagePullSecrets: [${NGC_SECRET}]
    config: |
      {
        "configList": [
HEREDOC
  NETWORKS=${#NETOP_NETLIST[@]}
  COMMA=","
  for DEVDEF in ${NETOP_NETLIST[@]};do
    IFS=',' read NIDX DEVICEID HCAMAX DEVNAMES <<< ${DEVDEF}
    DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
    let NETWORKS=NETWORKS-1
    [ ${NETWORKS} -le 0 ] && COMMA=""
    HCAMAX=${HCAMAX:=${NETOP_HCAMAX}}
cat << HEREDOC >> ${FILE}
          {
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "rdmaHcaMax": ${HCAMAX},
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              "ifNames": ["${DEVNAMES}"],
              "linkTypes": [${LINK_TYPES}],
              "isRdma": true
            }
          }${COMMA}
HEREDOC
  done
cat << HEREDOC >> ${FILE}
        ]
      }
HEREDOC
  ;;
hostdev_rdma_sriov)
cat << HEREDOC >> ${FILE}
  sriovDevicePlugin:
    image: sriov-network-device-plugin
    repository: $(get_repository sriov-network-device-plugin required)
    version: $(get_release_tag sriov-network-device-plugin)
    imagePullSecrets: [${NGC_SECRET}]
    config: |
      {
        "resourceList": [
HEREDOC
  NETWORKS=${#NETOP_NETLIST[@]}
  COMMA=","
  for DEVDEF in ${NETOP_NETLIST[@]};do
    IFS=',' read NIDX DEVICEID NETOP_HCAMAX DEVNAMES <<< ${DEVDEF}
    let NETWORKS=NETWORKS-1
    [ ${NETWORKS} -le 0 ] && COMMA=""
    if [[ "${DEVNAMES}" == *:* ]];then
      PCI_ADDRS='"pciAddresses": ["'${DEVNAMES}'"]'
      PF_NAMES='"pfNames": []'
    else
      PCI_ADDRS='"pciAddresses": []'
      PF_NAMES='"pfNames": [ "'${DEVNAMES}'" ]'
    fi
cat << HEREDOC >> ${FILE}
          {
            "resourcePrefix": "nvidia.com",
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              ${PF_NAMES},
              ${PCI_ADDRS},
              "isRdma": true
            }
          }${COMMA}
HEREDOC
  done
cat << HEREDOC >> ${FILE}
        ]
      }
HEREDOC
  ;;
esac
