#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NODENAME}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} label node ${1} ${NETOP_NODESELECTOR}="${NETOP_NODESELECTOR_VAL}"
