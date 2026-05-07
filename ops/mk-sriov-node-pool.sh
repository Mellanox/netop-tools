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
cat << HEREDOC
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkPoolConfig
metadata:
  name: node-pool-unavailable-config
  namespace: ${NETOP_NAMESPACE}
spec:
  maxUnavailable: ${QUOTE}${NETOP_SRIOV_NODE_POOL}${QUOTE}
  nodeSelector:
    matchExpressions:
      - key: ${NETOP_NODESELECTOR}
        operator: Exists
HEREDOC
if [ "${RDMASHAREDMODE}" == "false" ];then
cat << HEREDOC
  rdmaMode: exclusive
HEREDOC
fi
}
case ${USECASE} in
sriovnet_rdma|sriovibnet_rdma)
   sriov_node_pool > ${NETOP_SRIOV_NODE_POOL_FILE}
   echo "${NETOP_SRIOV_NODE_POOL_FILE}" > netop_sriov_pool_files
   ;;
*)
   rm -f netop_sriov_pool_files
   ;;
esac
