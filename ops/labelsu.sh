#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NODENAME} {SU}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} label node ${1} node.su/${2}=""
