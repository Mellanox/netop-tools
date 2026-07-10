#!/bin/bash
#
# restart k8 master
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

./ins-k8master.sh master
./ins-k8master.sh init
./ins-k8master.sh calico
./ins-k8master.sh netop
#./ins-k8master.sh debug
${K8CL} get nodes
