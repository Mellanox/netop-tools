#!/bin/bash
#
# apply the crds
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
DIRCRD="${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart/network-operator"
${docmd} ${K8CL} apply -f ${DIRCRD}/crds
case "${USECASE}" in
sriovnet_rdma|sriovib_net)
  ${docmd} ${K8CL} apply -f ${DIRCRD}/charts/sriov-network-operator/crds
esac
if [ "${NIC_CONFIG_ENABLE}" = "true" ];then
  ${docmd} ${K8CL} apply -f ${DIRCRD}/charts/nic-configuration-operator-chart/crds
fi
if [ "${MAINTENANCE_OPERATOR_ENABLE}" = "true" ];then
  ${docmd} ${K8CL} apply -f ${DIRCRD}/charts/maintenance-operator-chart/crds
fi
