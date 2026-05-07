#!/bin/bash
#
# apply the crds
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
DIRCRD="${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart/network-operator"
${docmd} ${K8CL} apply -f ${DIRCRD}/crds
case "${USECASE}" in
sriovnet_rdma|sriovibnet_rdma)
  case ${NETOP_VERSION} in
  25.10.*|26.1.*|26.4.*)
    ${docmd} ${K8CL} apply -f ${DIRCRD}/charts/sriov-network-operator/crds
     ;;
  *)
     ;;
  esac
esac
if [ "${NIC_CONFIG_ENABLE}" = "true" ];then
  ${docmd} ${K8CL} apply -f ${DIRCRD}/charts/nic-configuration-operator-chart/crds
fi
if [ "${MAINTENANCE_OPERATOR_ENABLE}" = "true" ];then
  ${docmd} ${K8CL} apply -f ${DIRCRD}/charts/maintenance-operator-chart/crds
fi
if [ "${NIC_NODE_POLICY_ENABLE}" = "true" ];then
  case ${NETOP_VERSION} in
    26.4.*)
      NNP_CRD="${DIRCRD}/crds/mellanox.com_nicnodepolicies.yaml"
      if [ -f "${NNP_CRD}" ];then
        ${docmd} ${K8CL} apply -f "${NNP_CRD}"
      else
        echo "WARNING: NicNodePolicy CRD not found: ${NNP_CRD}"
      fi
      ;;
  esac
fi
