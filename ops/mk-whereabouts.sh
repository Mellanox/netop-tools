#!/bin/bash
#
# use ${IPAM_TYPE} install of ipam for small clusters
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
FILE="./${IPAM_TYPE}-${NETOP_APP_NAMESPACE}.yaml"
cat << HEREDOC > ${FILE}
apiVersion: mellanox.com/v1alpha1
kind: ${NETOP_NETWORK_TYPE}
metadata:
  name: ${NETOP_NETWORK_NAME}
spec:
  networkNamespace: "${NETOP_APP_NAMESPACE}"
  resourceName: "${NETOP_NETWORK_NAME}"
  ipam: |
    {
      "type": "${IPAM_TYPE}",
      "datastore": "kubernetes",
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/${IPAM_TYPE}.d/${IPAM_TYPE}.kubeconfig"
      },
      "range": "${NETOP_NETWORK_RANGE}",
      "exclude": [ ${NETOP_NETWORK_EXCLUDE} ],
      "log_file" : "/var/log/${IPAM_TYPE}.log",
      "log_level" : "info"
    }
HEREDOC
cat ${FILE}
