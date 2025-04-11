#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
echo NetworkAttachmentDefinitions
${K8CL} get Network-Attachment-Definitions -A
echo "NETOP_NETWORK_TYPE:${NETOP_NETWORK_TYPE}"
${K8CL} get ${NETOP_NETWORK_TYPE} -A
echo "get NicClusterPolicy"
${K8CL} get NicClusterPolicy nic-cluster-policy
echo "check node ${NETOP_RESOURCE} device status"
NODES=`${K8CL} get nodes | grep worker | grep -v SchedulingDisabled | cut -d' ' -f1`
for NODE in ${NODES};do
  echo "node:${NODE}"
  ${K8CL} describe node ${NODE} | grep ${NETOP_RESOURCE}
  ${NETOP_ROOT_DIR}/ops/checkippool.sh ${NODE}
  ${K8CL} get pods -o=custom-columns='NAME:metadata.name,NODE:spec.nodeName,NETWORK-STATUS:metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status'  -A  --field-selector spec.nodeName=${NODE}
done
