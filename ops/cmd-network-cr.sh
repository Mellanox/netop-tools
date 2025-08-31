#!/bin/bash
#
# setup the host networks, and make the ip pool
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function runCmds()
{
  DIR="${NETOP_ROOT_DIR}/usecase/${USECASE}"
  FILE_LIST="${DIR}/${2}"
  if [ -f ${FILE_LIST} ];then
    for FILE in $(cat ${FILE_LIST});do
      WORK="${DIR}/${FILE}"
      if [ -f ${WORK} ];then
        ${docmd} ${K8CL} ${1} -f "${WORK}"
      else
        echo "ERROR:${WORK} not found"
      fi
    done
  else
    echo "ERROR:${FILE_LIST} not found"
  fi
}
function cmdNetworkCRDs()
{
  runCmds ${1} netop_network_files
}
#
# make sure the ip pool is created
#
function cmdIPAM_CRDs()
{
  if [ "${IPAM_TYPE}" = "nv-ipam" ];then
    runCmds ${1} netop_ippool_files
  fi
}
function cmdSriovNodePolicy()
{
  if [ "${NETOP_BCM_CONFIG}" == false ];then
    runCmds ${1} netop_nodepolicy_files
  fi
###  # according to Ivan,
###  # Network-Attachment-Definition generated automatically, except for ib-sriov-cni and pkey
###  #   ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-network-attachment.sh ${NIDX}
###  #   ${K8CL} ${1} set-last-applied -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml" --create-annotation
###  #   ${K8CL} ${1} -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml"
### 
}
