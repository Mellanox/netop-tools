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
kubectl label node ${1} node-role.kubernetes.io/worker=""
kubectl taint nodes ${1} node-role.kubernetes.io/control-plane-
