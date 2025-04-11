#!/bin/bash
#
# apply config changes, upgrade network-operator, apply network
#
NS="nvidia-network-operator"
${NETOP_ROOT_DIR}/ops/mk-values.sh
cd ..
./upgrade/upgrade-network-operator.sh
cd uc
function getpod()
{
  kubectl -n ${NS} get pods | grep rdma | cut -d' ' -f1
}
kubectl -n ${NS} delete pod $(getpod)
sleep 3
kubectl -n ${NS} logs $(getpod)
./networkcfg.sh
