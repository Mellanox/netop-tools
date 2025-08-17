#!/bin/bash
#
# setup the host networks, and make the ip pool
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function cmdNetworkCRDs()
{
  for NETOP_SU in ${NETOP_SULIST[@]};do
    FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_FILE}"
    if [ -f ${FILE} ];then
      ${docmd} ${K8CL} ${1} -f "${FILE}"
    else
      echo "ERROR:${FILE} not found"
    fi
  done
}
#
# make sure the ip pool is created
#
function cmdIPAM_CRDs()
{
  if [ "${IPAM_TYPE}" = "nv-ipam" ];then
    for NETOP_SU in ${NETOP_SULIST[@]};do
      FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_IPPOOL_FILE}"
      if [ -f ${FILE} ];then
        ${docmd} ${K8CL} ${1} -f "${FILE}"
      else
        echo "ERROR:${FILE} not found"
      fi
    done
  fi
}
function cmdSriovNodePolicy()
{
  if [ "${NETOP_BCM_CONFIG}" == false ];then
    for NETOP_SU in ${NETOP_SULIST[@]};do
      FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NODEPOLICY_FILE}"
      if [ -f ${FILE} ];then
        ${docmd} ${K8CL} ${1} -f "${FILE}"
      else
        echo "ERROR:${FILE} not found"
      fi
    done
  fi
###  # according to Ivan,
###  # Network-Attachment-Definition generated automatically, except for ib-sriov-cni and pkey
###  #   ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-network-attachment.sh ${NIDX}
###  #   ${K8CL} ${1} set-last-applied -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml" --create-annotation
###  #   ${K8CL} ${1} -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml"
### 
}
