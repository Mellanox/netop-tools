#!/bin/bash
#
# apply config changes, upgrade network-operator, apply network
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
NS="nvidia-network-operator"
${NETOP_ROOT_DIR}/ops/mk-values.sh
cd ..
./upgrade/upgrade-network-operator.sh
cd uc
function getpod()
{
  ${K8CL} -n ${NS} get pods | grep rdma | cut -d' ' -f1
}
${K8CL} -n ${NS} delete pod $(getpod)
sleep 3
${K8CL} -n ${NS} logs $(getpod)
./networkcfg.sh
