#!/bin/bash
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
  linkState: enable
  ipam: |
    {
      "type": "${IPAM_TYPE}",
      "datastore": "kubernetes",
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/${IPAM_TYPE}.d/${IPAM_TYPE}.kubeconfig"
      },
      "range": "${NETOP_NETWORK_RANGE}",
      "exclude": [],
      "log_file": "/var/log/${IPAM_TYPE}.log",
      "log_level": "info"
    }
HEREDOC
# "gateway": "${NETOP_NETWORK_GW}" # for ipam config above may need to set depending on fabric design
#kubectl get sriovnetwork -A
#kubectl -n ${NETOP_NAMESPACE} get sriovnetworknodestates.sriovnetwork.openshift.io -o yaml
#kubectl get pod -n ${NETOP_NAMESPACE} | grep sriov