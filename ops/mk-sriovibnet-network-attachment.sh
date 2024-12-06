#!/bin/bash
#
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NETWORK NDX} {NETOP_APP_NAMESPACE}"
  echo "example:$0 a default"
  exit 1
fi
NDX=${1}
shift
NETOP_APP_NAMESPACE=${1}
shift
FILE="./Network-Attachment-Definitions-${NDX}-${NETOP_APP_NAMESPACE}.yaml"
cat << HEREDOC > ${FILE}
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ${NETOP_NETWORK_NAME}-${NDX}
  namespace: ${NETOP_APP_NAMESPACE}
  annotations:
    k8s.v1.cni.cncf.io/resourceName: nvidia.com/${NETOP_RESOURCE}
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "name": "${NETOP_NETWORK_NAME}-${NDX}",
      "plugins": [
        {
          "type": "ib-sriov",
          "link_state":"enable",
          "ibKubernetesEnabled":true,
          "ipam": {
            "type": "${IPAM_TYPE}",
            "poolName": "${NETOP_NETWORK_POOL}"
          }
        }
      ]
    }
HEREDOC
