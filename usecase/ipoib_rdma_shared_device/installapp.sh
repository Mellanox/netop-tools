#!/bin/bash
#
# deploy pod.yaml configuration file for such a deployment:
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

NAME=${1}
shift
if [ "${NAME}" = "" ];then
  echo "usage:$0 {podname}"
  exit 1
fi
kubectl apply -f ./apps/${NAME}.yaml
