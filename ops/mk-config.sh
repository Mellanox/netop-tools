#!/bin/bash
#
# install the network operator.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${NETOP_ROOT_DIR}/ops/mk-values.sh
${NETOP_ROOT_DIR}/ops/mk-nic-cluster-policy.sh
if [ "${NIC_CONFIG_ENABLE}" = "true" ];then
  ${NETOP_ROOT_DIR}/ops/mk-nic-config.sh
else
  for DEVICE_TYPE in ${DEVICE_TYPES[@]};do
    rm -f "nic-config-crd-${DEVICE_TYPE}.yaml"
  done
fi
NETOP_NICNODE_FILES=()
if [ ${#NETOP_NODEPOOLS[@]} -gt 0 ]; then
  _IPPOOLS_DONE=false
  for NETLIST_VAR in "${NETOP_NODEPOOLS[@]}"; do
    _SUFFIX="${NETLIST_VAR#NETOP_NETLIST}"
    POOL_ID="${_SUFFIX#_}"
    export NETOP_ACTIVE_POOL="${POOL_ID}"
    export NIC_NODE_POLICY_FILE="nic-node-policy${POOL_ID:+-${POOL_ID}}.yaml"
    export NETOP_SRIOV_NODE_POOL_FILE="sriov-node-pool-config${POOL_ID:+-${POOL_ID}}.yaml"
    case ${NETOP_VERSION} in
      26.4.*)
        ${NETOP_ROOT_DIR}/ops/mk-nic-node-policy.sh
        NETOP_NICNODE_FILES+=("${NIC_NODE_POLICY_FILE}")
        ;;
    esac
    # Network CRs and IPPools are shared by resource/network name across
    # node pools. Only the per-pool node policies vary by device list.
    if [ "${_IPPOOLS_DONE}" = "true" ]; then
      export NETOP_SKIP_IPPOOL=true
    else
      unset NETOP_SKIP_IPPOOL
      _IPPOOLS_DONE=true
    fi
    ${NETOP_ROOT_DIR}/ops/mk-network-cr.sh
    ${NETOP_ROOT_DIR}/ops/mk-sriov-node-pool.sh
  done
  unset NETOP_ACTIVE_POOL NIC_NODE_POLICY_FILE NETOP_SRIOV_NODE_POOL_FILE NETOP_SKIP_IPPOOL
else
  ${NETOP_ROOT_DIR}/ops/mk-network-cr.sh
  ${NETOP_ROOT_DIR}/ops/mk-sriov-node-pool.sh
  case ${NETOP_VERSION} in
    26.4.*)
      if [ "${NIC_NODE_POLICY_ENABLE}" = "true" ];then
        ${NETOP_ROOT_DIR}/ops/mk-nic-node-policy.sh
        NETOP_NICNODE_FILES+=("${NIC_NODE_POLICY_FILE}")
      else
        rm -f "${NIC_NODE_POLICY_FILE}"
      fi
      ;;
    *)
      rm -f "${NIC_NODE_POLICY_FILE}"
      ;;
  esac
fi
if [ ${#NETOP_NICNODE_FILES[@]} -gt 0 ]; then
  echo "${NETOP_NICNODE_FILES[@]}" > netop_nicnode_files
else
  rm -f netop_nicnode_files
fi
if [ "${DRA_ENABLE}" = "true" ]; then
  case ${NETOP_VERSION} in
    26.4.*)
      ${NETOP_ROOT_DIR}/ops/mk-dra-cr.sh
      ;;
  esac
else
  rm -f netop_dra_files
fi
