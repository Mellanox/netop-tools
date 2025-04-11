#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NODENAME}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} label nodes ${1} node-role.kubernetes.io/control-plane=""
