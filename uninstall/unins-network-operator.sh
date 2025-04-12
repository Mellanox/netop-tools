#!/bin/bash
#
# uninstall the network-operator and remove the namespace
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

function del_single_crd()
{
  CRD="$1"
  
  while read RESOURCE rest;do
    ${K8CL} -n ${NETOP_NAMESPACE} delete ${CRD} ${RESOURCE}
  done < <(${K8CL} -n ${NETOP_NAMESPACE} get ${CRD} --no-headers)

  ${K8CL} delete crd ${CRD}
}

function del_sriovnet()
{
  ${K8CL} delete --force sriovnetwork -n ${NETOP_NAMESPACE} ${NETOP_NETWORK}
  ${K8CL} patch crd/sriovnetworks.sriovnetwork.openshift.io -p '{"metadata":{"finalizers":[]}}' --type=merge
}

${K8CL} delete crd `${NETOP_ROOT_DIR}/ops/getcrds.sh | egrep 'sriov|mellanox.com|nodefeature' | cut -d' ' -f1`

del_single_crd network-attachment-definitions.k8s.cni.cncf.io

if [ "${CREATE_CONFIG_ONLY}" = "1" ];then
  exit 0
fi

del_single_crd nicdevices.configuration.net.nvidia.com
del_single_crd nicconfigurationtemplates.configuration.net.nvidia.com
del_single_crd nodemaintenances.maintenance.nvidia.com
del_single_crd maintenanceoperatorconfigs.maintenance.nvidia.com

${K8CL} delete --force NicClusterPolicy nic-cluster-policy
${K8CL} delete --force ns "${NETOP_NAMESPACE}"
${NETOP_ROOT_DIR}/uninstall/delstucknamespace.sh "${NETOP_NAMESPACE}"
helm uninstall network-operator -n ${NETOP_NAMESPACE} --no-hooks
