#!/bin/bash
#
# Label a worker node and assign it to a NETOP node pool.
#
if [ "$#" -lt 2 ];then
  echo "usage:$0 {NODENAME} {POOL_ID|NETOP_NETLIST_POOL_ID}"
  exit 1
fi

source ${NETOP_ROOT_DIR}/global_ops.cfg

NODE_NAME="${1}"
POOL_ID="${2#NETOP_NETLIST}"
POOL_ID="${POOL_ID#_}"
POOL_LABEL_VALUE="${POOL_ID,,}"
POOL_SELECTOR_VAR="NETOP_NODESELECTOR_${POOL_ID}"
POOL_SELECTOR_VAL_VAR="NETOP_NODESELECTOR_VAL_${POOL_ID}"
POOL_SELECTOR="${!POOL_SELECTOR_VAR:-${NETOP_NODEPOOL_LABEL_KEY:-netop.nvidia.com/pool}}"
POOL_SELECTOR_VAL="${!POOL_SELECTOR_VAL_VAR:-${POOL_LABEL_VALUE}}"

${K8CL} label node "${NODE_NAME}" "${NETOP_NODESELECTOR}=${NETOP_NODESELECTOR_VAL}" --overwrite
${K8CL} label node "${NODE_NAME}" "${POOL_SELECTOR}=${POOL_SELECTOR_VAL}" --overwrite
