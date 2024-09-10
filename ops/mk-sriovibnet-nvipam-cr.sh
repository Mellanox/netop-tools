#!/bin/bash -x
#
# configure the secondary network
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NETWORK_NIDX_LIST}"
  echo "example:$0 a b c d e f g h"
  exit 1
fi
for NIDX in ${*};do
cat <<HEREDOC> "${NETOP_NETWORK_NAME}-${NIDX}"-cr.yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: ${NETOP_NETWORK_TYPE}
metadata:
  name: "${NETOP_NETWORK_NAME}-${NIDX}"
  namespace: ${NETOP_NAMESPACE}
spec:
  networkNamespace: "${NETOP_APP_NAMESPACE}"
  resourceName: "${NETOP_RESOURCE}_${NIDX}"
  ipam: |
    {
      "datastore": "kubernetes",
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/${IPAM_TYPE}.d/${IPAM_TYPE}.kubeconfig"
      },
      "log_file": "/tmp/${NETWORK_TYPE}.log",
      "log_level": "debug",
      "type": "${IPAM_TYPE}",
      "poolName": "${NETOP_NETWORK_POOL}"
    }
HEREDOC
done