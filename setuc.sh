#!/bin/bash
#
# install k8 master for first time
#
if [ -z ${NETOP_ROOT_DIR} ];then
    echo "NETOP_ROOT_DIR variable is not set"
    exit 1
fi

source ${NETOP_ROOT_DIR}/global_ops.cfg

rm -f uc
ln -s ${NETOP_ROOT_DIR}/usecase/${USECASE} ${NETOP_ROOT_DIR}/uc
