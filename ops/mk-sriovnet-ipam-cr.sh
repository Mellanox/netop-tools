#!/bin/bash
#
# configure the secondary network
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/mk-ipam-cr.sh
if [ "$#" -ne 4 ];then
  echo "usage:$0 {NETWORK_NAME} {IPPOOL_NAME} {NETWORK INDEX} {NETOP_APP_NAMESPACE}"
  echo "example:$0 a default"
  exit 1
fi
NETWORK_NAME=${1}
shift
IPPOOL_NAME=${1}
shift
NIDX=${1}
shift
NETOP_APP_NAMESPACE=${1}
shift

cat <<HEREDOC1
---
apiVersion: sriovnetwork.openshift.io/v1
kind: ${NETOP_NETWORK_TYPE}
metadata:
  name: "${NETWORK_NAME}"
  namespace: ${NETOP_NAMESPACE}
spec:
HEREDOC1
if [ "${NETOP_NETWORK_TYPE}" = "SriovNetwork" ];then
  echo "  vlan: ${NETOP_NETWORK_VLAN}"
else
  echo "  linkState: enable"
fi
meta_plugins 
cat <<HEREDOC4
  networkNamespace: "${NETOP_APP_NAMESPACE}"
  resourceName: "${NETOP_RESOURCE}_${NIDX}"
HEREDOC4
mk_ipam_cr ${IPPOOL_NAME}
