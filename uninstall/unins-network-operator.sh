#!/bin/bash
#
# uninstall the network-operator and remove the namespace
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function del_network-ad()
{
  NETWORK_AD="network-attachment-definitions.k8s.cni.cncf.io"
  CRDS=$(${K8CL} get ${NETWORK_AD} | grep -v NAME | cut -d' ' -f1)
  for CRD in ${CRDS};do
    ${K8CL} delete ${NETWORK_AD} $(kubectl get ${NETWORK_AD} | grep -v NAME | cut -d' ' -f1)
  done
  ${K8CL} delete crd ${NETWORK_AD}
}
function del_sriovnet()
{
  ${K8CL} delete --force sriovnetwork -n ${NETOP_NAMESPACE} ${NETOP_NETWORK}
  ${K8CL} patch crd/sriovnetworks.sriovnetwork.openshift.io -p '{"metadata":{"finalizers":[]}}' --type=merge
}
helm uninstall network-operator -n ${NETOP_NAMESPACE} --no-hooks
#${NETOP_ROOT_DIR}/uninstall/delcrds.sh   # no longer add crds, so nolonger delete
${K8CL} delete --force NicClusterPolicy nic-cluster-policy
#
# manually deleting crds
#
#${NETOP_ROOT_DIR}/ops/getcrds.sh
${NETOP_ROOT_DIR}/usecase/${USECASE}/delete-network-cr.sh
${K8CL} delete crd `${NETOP_ROOT_DIR}/ops/getcrds.sh | egrep 'sriov|mellanox.com|nodefeature' | cut -d' ' -f1`
del_network-ad
${K8CL} delete --force ns "${NETOP_NAMESPACE}"
${NETOP_ROOT_DIR}/uninstall/delstucknamespace.sh "${NETOP_NAMESPACE}"
