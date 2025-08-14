#!/bin/bash
#
# by default controlplane nodes are NOT schedulable for worker tasks
# label the controlplane as a worker
# remove the node-role.kubernetes.io/control-plane:NoSchedule Taint makes it scheduleable
#
# Taints:             node-role.kubernetes.io/control-plane:NoSchedule
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NODENAME}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} label node ${1} ${NETOP_NODESELECTOR}="${NETOP_NODESELECTOR_VAL}"
${K8CL} taint nodes ${1} node-role.kubernetes.io/control-plane-
