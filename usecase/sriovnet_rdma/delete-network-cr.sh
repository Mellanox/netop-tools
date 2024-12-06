#!/bin/bash -x
#
# delete the host networks crs, and the ip pool
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
#
# delete the resources defined in the SriovNetwork configuration files
#   sriov node policy file
#   NetworkAttachmentDefinition file
#   sriov network CRD file
#

for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/sriovnet-node-policy-${NIDX}.yaml"
  if [ -f ${FILE} ];then
    kubectl delete -f ${FILE}
  else
    echo "WARNING:not found:${FILE}"
  fi
  for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
    FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-cr.yaml"
    if [ -f ${FILE} ];then
      kubectl delete -f ${FILE}
    else
      echo "WARNING:not found:${FILE}"
    fi
  done
done
#
# make sure the ip pool is created
#
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool.yaml"
  if [ -f ${FILE} ];then
    kubectl delete -f ${FILE}
  else
    echo "WARNING:not found:${FILE}"
  fi
fi
#
# verify the network devices
#
${NETOP_ROOT_DIR}/ops/getnetwork.sh
