#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function sriov_node_pool()
{
if [[ "${NETOP_SRIOV_NODE_POOL}" == *% ]];then
  QUOTE='"'
else
  QUOTE=""
fi
POOL_CONFIG_NAME="${NETOP_ACTIVE_POOL:+${NETOP_ACTIVE_POOL}-}node-pool-unavailable-config"
cat << HEREDOC
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkPoolConfig
metadata:
  name: ${POOL_CONFIG_NAME}
  namespace: ${NETOP_NAMESPACE}
spec:
  maxUnavailable: ${QUOTE}${NETOP_SRIOV_NODE_POOL}${QUOTE}
  nodeSelector:
    matchExpressions:
      - key: ${NETOP_NODESELECTOR}
        operator: Exists
HEREDOC
}
case ${USECASE} in
sriovnet_rdma|sriovibnet_rdma)
   sriov_node_pool > ${NETOP_SRIOV_NODE_POOL_FILE}
   ;;
esac
