#!/bin/bash
#
# deploy pod.yaml configuration file for such a deployment:
#
NAME=${1}
shift
if [ "${NAME}" = "" ];then
  echo "usage:$0 {podname}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} apply -f ${NETOP_ROOT_DIR}/uc/apps/${NAME}.yaml
