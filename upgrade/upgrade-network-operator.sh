#!/bin/bash -x
#
# Go to NGC catalog
# Down load
#
# https://catalog.ngc.nvidia.com/orgs/nvidia/teams/cloud-native/helm-charts/network-operator
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/cordon.sh
cordon
#../install/ins-netop-chart.sh
pushd .
export NETOP_CHART_DIR="${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart"
cd ${NETOP_CHART_DIR}
kubectl scale deployment --replicas=0 -n ${NETOP_NAMESPACE} network-operator
popd
pushd .
USECASE_DIR="${NETOP_ROOT_DIR}/usecase/${USECASE}"
cd ${USECASE_DIR}
${NETOP_ROOT_DIR}/ops/mk-values.sh
${NETOP_ROOT_DIR}/ops/mk-nic-cluster-policy.sh
${NETOP_ROOT_DIR}/ops/mk-network-cr.sh
kubectl apply -f NicClusterPolicy.yaml
popd
#helm upgrade
#
# the yaml file needs to be the custom network operator configuration to overider the defaults
#
cd ${NETOP_CHART_DIR}/network-operator
helm upgrade -n ${NETOP_NAMESPACE} network-operator nvidia/network-operator --version ${NETOP_VERSION} -f ./values.yaml -f ${USECASE_DIR}/values.yaml
uncordon
