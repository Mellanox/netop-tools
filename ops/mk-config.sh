#!/bin/bash
#
# install the network operator.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${NETOP_ROOT_DIR}/ops/mk-values.sh
${NETOP_ROOT_DIR}/ops/mk-nic-cluster-policy.sh
${NETOP_ROOT_DIR}/ops/mk-network-cr.sh
${NETOP_ROOT_DIR}/ops/mk-sriov-node-pool.sh
if [ "${NIC_CONFIG_ENABLE}" = "true" ];then
  ${NETOP_ROOT_DIR}/ops/mk-nic-config.sh
else
  for DEVICE_TYPE in ${DEVICE_TYPES[@]};do
    rm -f "nic-config-crd-${DEVICE_TYPE}.yaml"
  done
fi
case ${NETOP_VERSION} in
  26.4.*)
    if [ "${NIC_NODE_POLICY_ENABLE}" = "true" ];then
      ${NETOP_ROOT_DIR}/ops/mk-nic-node-policy.sh
    else
      rm -f "${NIC_NODE_POLICY_FILE}"
    fi
    ;;
  *)
    rm -f "${NIC_NODE_POLICY_FILE}"
    ;;
esac
