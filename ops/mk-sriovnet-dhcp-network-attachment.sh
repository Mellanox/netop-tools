#!/bin/bash
#
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NETWORK_DEV}"
  echo "example:$0 a"
  exit 1
fi
DEV=${1}
shift
source ${NETOP_ROOT_DIR}/global_ops.cfg
for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
FILE="./Network-Attachment-Definitions-${DEV}--${NETOP_APP_NAMESPACE}.yaml"
# Copyright (c) NVIDIA Corporation 2023
# https://github.com/k8snetworkplumbingwg/multus-cni/tree/master/examples#passing-down-device-information
cat << HEREDOC > ${FILE}
---
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: ${NETOP_NETWORK_NAME}-${DEV}
  namespace: ${NETOP_APP_NAMESPACE}
  annotations:
    k8s.v1.cni.cncf.io/resourceName: nvidia.com/${NETOP_RESOURCE}
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "name": "${NETOP_NETWORK_NAME}-${DEV}",
      "plugins": [
        {
          "type": "sriov",
          "vlan": ${NETOP_VLAN},
          "spoofchk": "off",
          "vlanQoS": 0,
          "link_state": "enable",
          "logLevel": "info",
          "ipam": {
            "type": "dhcp",
            "daemonSocketPath": "/run/cni/dhcp.sock",
            "request": [
              {
                "skipDefault": false,
                "option": "classless-static-routes"
              }
            ],
            "provide": [
              {
                "option": "host-name",
                "fromArg": "K8S_POD_NAME"
              }
            ]
          }
        }
      ]
    }
HEREDOC
done
