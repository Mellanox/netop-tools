#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
if [ $# -ne 2 ];then
  echo "usage:$0 {node} taint"
  exit 1
fi
${K8CL} taint nodes ${1} ${2}-
