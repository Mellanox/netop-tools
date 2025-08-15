#!/bin/bash
#
# by default control planes are NOT schedulable for worker tasks
# this script removes the controlplane node from the worker pool
# 
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NODENAME}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
# to make unschedulable, add the taint node-role.kubernetes.io/control-plane:NoSchedule
${K8CL} taint nodes ${1} node-role.kubernetes.io/control-plane:NoSchedule
# remove the worker label
${K8CL} label node ${1} ${NETOP_NODESELECTOR}-
