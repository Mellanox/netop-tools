#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
X=`kubectl get secret -n ${NETOP_NAMESPACE} | grep -c "${NGC_SECRET}"`
if [ "${X}" != "0" ];then
  kubectl delete secret ${NGC_SECRET} -n ${NETOP_NAMESPACE}
fi
