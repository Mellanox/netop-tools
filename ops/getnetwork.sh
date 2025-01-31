#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
echo NetworkAttachmentDefinitions
kubectl get Network-Attachment-Definitions -A
echo "NETOP_NETWORK_TYPE:${NETOP_NETWORK_TYPE}"
kubectl get ${NETOP_NETWORK_TYPE} -A
echo "get NicClusterPolicy"
kubectl get NicClusterPolicy nic-cluster-policy
echo "check node ${NETOP_RESOURCE} device status"
NODES=`kubectl get nodes | grep worker | grep -v SchedulingDisabled | cut -d' ' -f1`
for NODE in ${NODES};do
  echo "node:${NODE}"
  kubectl describe node ${NODE} | grep ${NETOP_RESOURCE}
  ${NETOP_ROOT_DIR}/ops/checkippool.sh ${NODE}
  kubectl get pods -o=custom-columns='NAME:metadata.name,NODE:spec.nodeName,NETWORK-STATUS:metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status'  -A  --field-selector spec.nodeName=${NODE}
done
