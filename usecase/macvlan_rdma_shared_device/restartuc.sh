#!/bin/bash
#
# apply config changes, upgrade network-operator, apply network
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
NS="nvidia-network-operator"
./delete-network-cr.sh
${NETOP_ROOT_DIR}/ops/mk-values.sh
cd ..
./upgrade/upgrade-network-operator.sh
cd uc
${K8CL} -n ${NS} delete ds rdma-shared-dp-ds
sleep 3
${K8CL} -n ${NS} logs $(getpod)
./apply-network-cr.sh
