#!/bin/bash -e
#
# apply the crds
#

source ${NETOP_ROOT_DIR}/global_ops.cfg
kubectl apply \
   -f ${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart/network-operator/crds \
   -f ${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart/network-operator/charts/sriov-network-operator/crds
