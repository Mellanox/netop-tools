#!/bin/bash -x
#
# use ${IPAM_TYPE} install of ipam for small clusters
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
cat << HEREDOC > ./${IPAM_TYPE}.yaml
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
      "exclude": [],
      "log_file" : "/var/log/${IPAM_TYPE}.log",
      "log_level" : "info"
    }
HEREDOC
cat ./${IPAM_TYPE}.yaml
