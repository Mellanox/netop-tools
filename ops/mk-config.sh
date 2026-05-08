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
if [ ${#NETOP_NODEPOOLS[@]} -gt 0 ]; then
  declare -A _FABRICS_DONE
  for NETLIST_VAR in "${NETOP_NODEPOOLS[@]}"; do
    _SUFFIX="${NETLIST_VAR#NETOP_NETLIST}"
    POOL_ID="${_SUFFIX#_}"
    export NETOP_ACTIVE_POOL="${POOL_ID}"
    export NIC_NODE_POLICY_FILE="nic-node-policy${POOL_ID:+-${POOL_ID}}.yaml"
    export NETOP_SRIOV_NODE_POOL_FILE="sriov-node-pool-config${POOL_ID:+-${POOL_ID}}.yaml"
    case ${NETOP_VERSION} in
      26.4.*)
        ${NETOP_ROOT_DIR}/ops/mk-nic-node-policy.sh
        ;;
    esac
    # Determine this pool's fabric label (same variable name as in global_ops.cfg lookup).
    # Pools sharing a fabric label share IPPools; generate them only on the first encounter.
    _FABRIC_VAR="NETOP_FABRIC_${POOL_ID}"
    _POOL_FABRIC="${!_FABRIC_VAR:-}"
    _FABRIC_KEY="${_POOL_FABRIC:-__unset__}"
    if [ "${_FABRICS_DONE[${_FABRIC_KEY}]+x}" = "x" ]; then
      export NETOP_SKIP_IPPOOL=true
    else
      unset NETOP_SKIP_IPPOOL
      _FABRICS_DONE["${_FABRIC_KEY}"]=1
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
      else
        rm -f "${NIC_NODE_POLICY_FILE}"
      fi
      ;;
    *)
      rm -f "${NIC_NODE_POLICY_FILE}"
      ;;
  esac
fi
