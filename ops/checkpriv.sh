#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {POD}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} get pod ${1} -o json | jq -r '.spec.containers[].securityContext.privileged'
