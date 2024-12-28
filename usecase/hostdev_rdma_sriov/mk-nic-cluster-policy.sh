#!/bin/bash
#
# nic cluster plocy file has migrated outof the values.yaml file
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
FILE="NicClusterPolicy.yaml"
cat << HEREDOC1 > ${FILE}
apiVersion: mellanox.com/v1alpha1
kind: NicClusterPolicy
metadata:
  name: nic-cluster-policy
spec:
  sriovDevicePlugin:
    image: sriov-network-device-plugin
    repository: ghcr.io/k8snetworkplumbingwg
    version: v3.8.0
    imagePullSecrets: []
    config: |
      {
        "resourceList": [
HEREDOC1
NETWORKS=${#NETOP_NETLIST[@]}
COMMA=","
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  DEVICEID=`echo ${DEVDEF}|cut -d',' -f2`
  NETOP_HCAMAX=`echo ${DEVDEF}|cut -d',' -f3`
  DEVNAMES=`echo ${DEVDEF}|cut -d',' -f4-12`
  DEVNAMES=`echo ${DEVNAMES} | sed 's/,/","/g'`
  let NETWORKS=NETWORKS-1
  if [ ${NETWORKS} -le 0 ];then
	  COMMA=""
  fi
cat << HEREDOC2 >> ${FILE}
          {
            "resourcePrefix": "nvidia.com",
            "resourceName": "${NETOP_RESOURCE}_${NIDX}",
            "selectors": {
              "vendors": ["${NETOP_VENDOR}"],
              "devices": [],
              "drivers": [],
              "pfNames": [],
              "pciAddresses": ["${DEVNAMES}"],
              "rootDevices": [],
              "linkTypes": [],
              "isRdma": true
            }
          }${COMMA}
HEREDOC2
done
cat << HEREDOC3 >> ${FILE}
        ]
      }
  secondaryNetwork:
    cniPlugins:
      image: plugins
      repository: ghcr.io/k8snetworkplumbingwg
      version: v1.5.0
      imagePullSecrets: []
    multus:
      image: multus-cni
      repository: ghcr.io/k8snetworkplumbingwg
      version: v4.1.0
      imagePullSecrets: []
HEREDOC3
if [ "${IPAM_TYPE}" = "whereabouts" ];then
cat << HEREDOC4 >> ${FILE}
    ipamPlugin:
      image: whereabouts
      repository: ghcr.io/k8snetworkplumbingwg
      version: v0.7.0
      imagePullSecrets: []
HEREDOC4
fi
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
cat << HEREDOC5 >> ${FILE}
  nvIpam:
    image: nvidia-k8s-ipam
    repository: ghcr.io/mellanox
    version: v0.2.0
    imagePullSecrets: []
    enableWebhook: false
HEREDOC5
fi
