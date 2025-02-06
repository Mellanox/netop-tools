#!/bin/bash -x
#
# setup the host networks, and make the ip pool
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/mk-network-ippool-cr.sh
#
# set the SriovNetwork configuration files
#   sriov node policy file
#   NetworkAttachmentDefinition file
#   sriov network CRD file
#
#   this is generated automatically, 
#   except for ib-sriov-cni and pkey
#   ${NETOP_ROOT_DIR}/ops/mk-sriovnet-network-attachment.sh ${NIDX}
#   kubectl apply set-last-applied -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml" --create-annotation
#   kubectl apply -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml"

for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  NDEV=`echo ${DEVDEF}|cut -d',' -f4-20`
  FILE=$( ${NETOP_ROOT_DIR}/ops/mk-sriovnet-node-policy.sh ${NIDX} ${NDEV} )
  echo ${FILE}
  for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
    FILE=$( ${NETOP_ROOT_DIR}/ops/mk-sriovnet-ipam-cr.sh ${NIDX} ${NETOP_APP_NAMESPACE} )
    echo ${FILE}
  done
done
mkNetworkIPPoolCRDs
