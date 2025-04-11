#!/bin/bash
#
# install k8 master for first time
#
if [ -z ${NETOP_ROOT_DIR} ];then
    echo "NETOP_ROOT_DIR variable is not set"
    exit 1
fi

source ${NETOP_ROOT_DIR}/global_ops.cfg

${NETOP_ROOT_DIR}/setuc.sh
${NETOP_ROOT_DIR}/restart/removek8master.sh
${NETOP_ROOT_DIR}/install/ins-k8master.sh master
${NETOP_ROOT_DIR}/install/ins-k8master.sh init
${NETOP_ROOT_DIR}/install/ins-k8master.sh calico
exit 0
${NETOP_ROOT_DIR}/install/ins-k8master.sh netop

kubectl get nodes
