#!/bin/bash
#
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
if [ "$#" -lt 1 ] || [ "$#" -gt 3 ];then
  echo "usage:$0 {NETWORK NIDX} [NETOP_SU] [NETOP_APP_NAMESPACE]"
  echo "example:$0 a su-1 default"
  exit 1
fi
NIDX=${1}
shift
NETOP_SU=${1:-}
if [ "$#" -gt 0 ];then
  shift
fi
SUTAG="${NETOP_SU:+-${NETOP_SU}}"
if [ "$#" -gt 0 ];then
  NETOP_APP_NAMESPACE_VALUES=( "${1}" )
else
  NETOP_APP_NAMESPACE_VALUES=( "${NETOP_APP_NAMESPACES[@]}" )
fi
for NETOP_APP_NAMESPACE in "${NETOP_APP_NAMESPACE_VALUES[@]}";do
FILE="./Network-Attachment-Definitions-${NIDX}-${NETOP_APP_NAMESPACE}.yaml"
cat << HEREDOC > ${FILE}
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ${NETOP_NETWORK_NAME}-${NIDX}
  namespace: ${NETOP_APP_NAMESPACE}
  annotations:
    k8s.v1.cni.cncf.io/resourceName: nvidia.com/${NETOP_RESOURCE}
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "name": "${NETOP_NETWORK_NAME}-${NIDX}",
      "plugins": [
        {
          "type": "ib-sriov",
          "link_state":"enable",
          "ibKubernetesEnabled":true,
          "ipam": {
            "type": "${IPAM_TYPE}",
            "poolName": "${NETOP_NETWORK_POOL}-${NIDX}${SUTAG}"
          }
        }
      ]
    }
HEREDOC
done
