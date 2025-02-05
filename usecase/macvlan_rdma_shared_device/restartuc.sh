#!/bin/bash -x
#
# apply config changes, upgrade network-operator, apply network
#
NS="nvidia-network-operator"
./delete-network-cr.sh
${NETOP_ROOT_DIR}/ops/mk-values.sh
cd ..
./upgrade/upgrade-network-operator.sh
cd uc
kubectl -n ${NS} delete ds rdma-shared-dp-ds
sleep 3
kubectl -n ${NS} logs $(getpod)
./apply-network-cr.sh
