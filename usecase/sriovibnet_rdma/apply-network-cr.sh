#!/bin/bash -x
#
# setup the host networks, and make the ip pool
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
#
# set the SriovNetwork configuration files
#   sriov node policy file
#   NetworkAttachmentDefinition file
#   sriov network CRD file
#
for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
  for DEVDEF in ${NETOP_NETLIST[@]};do
    NIDX=`echo ${DEVDEF}|cut -d',' -f1`
    NDEV=`echo ${DEVDEF}|cut -d',' -f4-20`
    FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/sriovibnet-node-policy-${NIDX}.yaml"
    kubectl apply -f "${FILE}"
# according to Ivan, this is generated automatically, except in the 
# The only case you need to do it manually it’s ib-sriov-cni and pkey
# ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-network-attachment.sh ${NIDX}
# kubectl apply set-last-applied -f "${DIR}//Network-Attachment-Definitions-${NIDX}.yaml" --create-annotation
    FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-cr.yaml"
    kubectl apply -f "${FILE}"
  done
done
#
# make sure the ip pool is created
#
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool.yaml"
  kubectl apply -f ${FILE}
fi
#
# verify the network devices
#
${NETOP_ROOT_DIR}/ops/getnetwork.sh
