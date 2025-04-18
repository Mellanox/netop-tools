#!/bin/bash
#
# ${1}=0    remove network-operator pod
# ${1}=1    start network-operator pod
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NUM_REPLICAS}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} -n ${NETOP_NAMESPACE} scale deployment network-operator --replicas ${1}
