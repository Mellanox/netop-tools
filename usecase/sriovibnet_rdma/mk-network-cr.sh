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

for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  NDEV=`echo ${DEVDEF}|cut -d',' -f4-20`
  ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-node-policy.sh ${NIDX} ${NDEV}
  DIR="${NETOP_ROOT_DIR}/usecase/${USECASE}"
  FILE="${DIR}/sriovibnet-node-policy-${NIDX}.yaml"
  echo ${FILE}
# this is generated automatically, 
# except for ib-sriov-cni and pkey
# ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-network-attachment.sh ${NIDX}
# kubectl apply set-last-applied -f "${DIR}//Network-Attachment-Definitions-${NIDX}.yaml" --create-annotation
  ${NETOP_ROOT_DIR}/ops/mk-sriovnet-ipam-cr.sh ${NIDX}
  FILE="${DIR}/${NETOP_NETWORK_NAME}-${NIDX}-cr.yaml"
  echo ${FILE}
done
#
# create ipam pool
#
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  ${NETOP_ROOT_DIR}/ops/mk-nvipam-pool.sh
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool.yaml"
  echo ${FILE}
fi
