#!/bin/bash
#
# setup the host networks, define the ip  pool
#
# For HostDeviceNetwork you'll need to define the SRIOV VFs on the worker nodes
# echo 0 > /sys/devices/pci0000:20/0000:20:01.5/0000:23:00.0/sriov_numvfs
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function init_file()
{
  if [ "${NETOP_TAG_VERSION}" == true ];then
    echo "# VERSION:${NETOP_VERSION}" > "${1}"
  else
    rm -f "${1}"
  fi
}
function IPPoolCRD()
{
  SUBNET_FILE="/tmp/subnets.$$"
  NETOP_IPPOOL_FILES=()
  IPPOOL_IDX=0
  if [ "${IPAM_TYPE}" = "nv-ipam" ];then
    for NETOP_SU in ${NETOP_SULIST[@]};do
      NUM_SUBNETS="${#NETOP_NETLIST[@]}"
      ${NETOP_ROOT_DIR}/ops/generate_subnets.sh "${NETOP_NETWORK_RANGE}" "${NUM_SUBNETS}" ${NETOP_NETWORK_GW} > ${SUBNET_FILE}
      LINE_NUM=1
      for NIDXDEF in ${NETOP_NETLIST[@]};do
        NIDX=$(echo ${NIDXDEF}|cut -d',' -f1)
        LINE=$(sed -n ${LINE_NUM}p ${SUBNET_FILE})
        RANGE=$(echo ${LINE}|cut -d' ' -f1)
        GW=$(echo ${LINE}|cut -d' ' -f3)
        IPPOOL_NAME=${NETOP_NETWORK_POOL}-${NIDX}-${NETOP_SU}
        FILE="ippool-${NIDX}-${NETOP_SU}.yaml"
        NETOP_IPPOOL_FILES[${IPPOOL_IDX}]="${FILE}"
        let IPPOOL_IDX=IPPOOL_IDX+1
        init_file ${FILE}
        case "${NVIPAM_POOL_TYPE}" in
        IPPool)
          ${NETOP_ROOT_DIR}/ops/mk-nvipam-pool.sh "${IPPOOL_NAME}" "${RANGE}" "${GW}" "${NETOP_PERNODE_BLOCKSIZE}" >> ${FILE}
          ;;
        CIDRPool)
          ${NETOP_ROOT_DIR}/ops/mk-nvipam-cidr.sh "${IPPOOL_NAME}" "${RANGE}" "${GW}" "${NETOP_PERNODE_BLOCKSIZE}" >> ${FILE}
          ;;
        esac
        let LINE_NUM=LINE_NUM+1
      done
      rm  -f ${SUBNET_FILE}
    done
  fi
  if [ ${#NETOP_IPPOOL_FILES[@]} -gt 0 ];then
    echo ${NETOP_IPPOOL_FILES[@]} > netop_ippool_files
  fi
}
#
# TODO:
# the NetworkAttachmentDefinition generated automatically, 
# except for ib-sriov-cni and pkey
#
function mkNetworkAttachmentDefinition()
{
  ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-network-attachment.sh ${NIDX}
  ${docmd} ${K8CL} apply set-last-applied -f "${DIR}//Network-Attachment-Definitions-${NIDX}.yaml" --create-annotation
}
#
# based on the NETOP_NETWORK_TYPE define the network CRDs
#
function NetworkCRD()
{
  NETOP_NETWORK_FILES=()
  NETWORK_IDX=0
  NETOP_NODEPOLICY_FILES=()
  POLICY_IDX=0
  for NETOP_SU in ${NETOP_SULIST[@]};do
    for NIDXDEF in ${NETOP_NETLIST[@]};do
      NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
      NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
      POLICY_NAME="${NETOP_NETWORK_NAME}-node-policy-${NIDX}-${NETOP_SU}"
      FILE="${POLICY_NAME}.yaml"
      case ${NETOP_NETWORK_TYPE} in
      SriovIBNetwork)
        NETOP_NODEPOLICY_FILES[${POLICY_IDX}]="${FILE}"
        let POLICY_IDX=POLICY_IDX+1
        init_file ${FILE} 
        ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-node-policy.sh ${POLICY_NAME} ${NIDX} ${NDEV} > ${FILE}
        ;;
      SriovNetwork)
        NETOP_NODEPOLICY_FILES[${POLICY_IDX}]="${FILE}"
        let POLICY_IDX=POLICY_IDX+1
        init_file ${FILE} 
        ${NETOP_ROOT_DIR}/ops/mk-sriovnet-node-policy.sh ${POLICY_NAME} ${NIDX} ${NDEV} > ${FILE}
        ;;
      esac
      for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
        NETWORK_NAME="${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}"
        FILE="${NETWORK_NAME}-cr.yaml"
        NETOP_NETWORK_FILES[${NETWORK_IDX}]="${FILE}"
        let NETWORK_IDX=NETWORK_IDX+1
        init_file ${FILE} 
        IPPOOL_NAME=${NETOP_NETWORK_POOL}-${NIDX}-${NETOP_SU}
        case ${NETOP_NETWORK_TYPE} in
        HostDeviceNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-hostdev-sriov-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NIDX} ${NETOP_APP_NAMESPACE} >> ${FILE}
          ;;
        IPoIBNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-ipoib-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NDEV} ${NIDX} ${NETOP_APP_NAMESPACE} >> ${FILE}
          ;;
        MacvlanNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-hostdev-macvlan-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NDEV} ${NETOP_APP_NAMESPACE} >> ${FILE}
          ;;
        SriovNetwork|SriovIBNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-sriovnet-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NIDX} ${NETOP_APP_NAMESPACE} >> ${FILE}
          ;;
        esac
      done
    done
  done
  if [ ${#NETOP_NODEPOLICY_FILES} -gt 0 ];then
    echo ${NETOP_NODEPOLICY_FILES[@]} > netop_nodepolicy_files
  fi
  if [ ${#NETOP_NETWORK_FILES} -gt 0 ];then
    echo ${NETOP_NETWORK_FILES[@]} > netop_network_files
  fi
}
function combinedIPPoolCRD()
{
  if [ -f netop_ippool_files ];then
    rm -f ${NETOP_IPPOOL_FILE}
    for FILE in $(cat netop_ippool_files);do
      cat ${FILE} >> ${NETOP_IPPOOL_FILE}
      rm -f ${FILE}
    done
    echo "${NETOP_IPPOOL_FILE}" > netop_ippool_files
  fi
}
function combineNodePolicy()
{
  if [ -f  netop_nodepolicy_files ];then
    rm -f ${NETOP_NODEPOLICY_FILE}
    for FILE in $(cat netop_nodepolicy_files);do
      cat ${FILE} >> ${NETOP_NODEPOLICY_FILE}
      rm -f ${FILE}
    done
    echo "${NETOP_NODEPOLICY_FILE}" > netop_nodepolicy_files
  fi
}
function combineNetwork()
{
  if [ -f  netop_network_files ];then
    rm -f ${NETOP_NETWORK_FILE}
    for FILE in $(cat netop_network_files);do
      cat ${FILE} >> ${NETOP_NETWORK_FILE}
      rm -f ${FILE}
    done
    echo "${NETOP_NETWORK_FILE}" > netop_network_files
  fi
}
function combinedNetworkCRD()
{
   combineNodePolicy
   combineNetwork
#
# combine to single file for BCM format
#
  if [ "${NETOP_BCM_CONFIG}" == true ];then
    cat ${NETOP_NODEPOLICY_FILE} ${NETOP_NETWORK_FILE} > /tmp/${NETOP_NETWORK_FILE}
    mv -f /tmp/${NETOP_NETWORK_FILE} ${NETOP_NETWORK_FILE}
    # cleanup
    rm -f ${NETOP_NODEPOLICY_FILE}
    rm -f netop_nodepolicy_files
  fi
}
IPPoolCRD
NetworkCRD
if [ "${NETOP_COMBINED}" == true ];then
  combinedIPPoolCRD
  combinedNetworkCRD
fi
