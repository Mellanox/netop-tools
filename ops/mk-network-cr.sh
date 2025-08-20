#!/bin/bash
#
# setup the host networks, define the ip  pool
#
# For HostDeviceNetwork you'll need to define the SRIOV VFs on the worker nodes
# echo 0 > /sys/devices/pci0000:20/0000:20:01.5/0000:23:00.0/sriov_numvfs
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function combinedIPPoolCRD()
{
  SUBNET_FILE="/tmp/subnets.$$"
  if [ "${IPAM_TYPE}" = "nv-ipam" ];then
    echo "# VERSION:${NETOP_VERSION}" > ${NETOP_IPPOOL_FILE}
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
        case "${NVIPAM_POOL_TYPE}" in
        IPPool)
          ${NETOP_ROOT_DIR}/ops/mk-nvipam-pool.sh "${IPPOOL_NAME}" "${RANGE}" "${GW}" "${NETOP_PERNODE_BLOCKSIZE}" >> ${NETOP_IPPOOL_FILE}
          ;;
        CIDRPool)
          ${NETOP_ROOT_DIR}/ops/mk-nvipam-cidr.sh "${IPPOOL_NAME}" "${RANGE}" "${GW}" "${NETOP_PERNODE_BLOCKSIZE}" >> ${NETOP_IPPOOL_FILE}
          ;;
        esac
        let LINE_NUM=LINE_NUM+1
      done
      rm  -f ${SUBNET_FILE}
    done
  fi
}
function IPPoolCRD()
{
  SUBNET_FILE="/tmp/subnets.$$"
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
        #echo "# VERSION:${NETOP_VERSION}" > ${FILE}
        rm -f ${FILE}
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
function combinedNetworkCRD()
{
  for NETOP_SU in ${NETOP_SULIST[@]};do
    echo "# VERSION:${NETOP_VERSION}" > ${NETOP_NODEPOLICY_FILE} 
    echo "# VERSION:${NETOP_VERSION}" > ${NETOP_NETWORK_FILE} 
    for NIDXDEF in ${NETOP_NETLIST[@]};do
      NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
      NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
      FILE="${NETOP_NETWORK_NAME}-node-policy-${NIDX}-${NETOP_SU}.yaml"
      case ${NETOP_NETWORK_TYPE} in
      SriovIBNetwork)
        ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-node-policy.sh ${FILE%%.yaml} ${NIDX} ${NDEV} >> ${NETOP_NODEPOLICY_FILE}
  name: ${FILE%%.yaml}
        ;;
      SriovNetwork)
        ${NETOP_ROOT_DIR}/ops/mk-sriovnet-node-policy.sh ${FILE%%.yaml} ${NIDX} ${NDEV} >> ${NETOP_NODEPOLICY_FILE}
        ;;
      esac
      for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
        NETWORK_NAME="${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}"
        IPPOOL_NAME=${NETOP_NETWORK_POOL}-${NIDX}-${NETOP_SU}
        case ${NETOP_NETWORK_TYPE} in
        HostDeviceNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-hostdev-sriov-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NIDX} ${NETOP_APP_NAMESPACE} >> ${NETOP_NETWORK_FILE}
          ;;
        IPoIBNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-ipoib-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NDEV} ${NIDX} ${NETOP_APP_NAMESPACE} >> ${NETOP_NETWORK_FILE}
          ;;
        MacvlanNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-hostdev-macvlan-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NDEV} ${NETOP_APP_NAMESPACE} >> ${NETOP_NETWORK_FILE}
          ;;
        SriovNetwork|SriovIBNetwork)
          ${NETOP_ROOT_DIR}/ops/mk-sriovnet-ipam-cr.sh ${NETWORK_NAME} ${IPPOOL_NAME} ${NIDX} ${NETOP_APP_NAMESPACE} >> ${NETOP_NETWORK_FILE}
          ;;
        esac
      done
    done
    #
    # combine to single file for BCM format
    #
    if [ "${NETOP_BCM_CONFIG}" == true ];then
      cat ${NETOP_NODEPOLICY_FILE} ${NETOP_NETWORK_FILE} > /tmp/${NETOP_NETWORK_FILE}
      mv -f /tmp/${NETOP_NETWORK_FILE} ${NETOP_NETWORK_FILE}
      rm -f ${NETOP_NODEPOLICY_FILE}
    fi
  done
}
#
# based on the NETOP_NETWORK_TYPE define the network CRDs
#
function NetworkCRD()
{
  for NETOP_SU in ${NETOP_SULIST[@]};do
    for NIDXDEF in ${NETOP_NETLIST[@]};do
      NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
      NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
      POLICY_NAME="${NETOP_NETWORK_NAME}-node-policy-${NIDX}-${NETOP_SU}"
      FILE="${POLICY_NAME}.yaml"
      #echo "# VERSION:${NETOP_VERSION}" > ${FILE} 
      rm -f ${FILE} 
      case ${NETOP_NETWORK_TYPE} in
      SriovIBNetwork)
        ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-node-policy.sh ${POLICY_NAME} ${NIDX} ${NDEV} > ${FILE}
        ;;
      SriovNetwork)
        ${NETOP_ROOT_DIR}/ops/mk-sriovnet-node-policy.sh ${POLICY_NAME} ${NIDX} ${NDEV} > ${FILE}
        ;;
      esac
      for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
        NETWORK_NAME="${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}"
        FILE="${NETWORK_NAME}-cr.yaml"
        #echo "# VERSION:${NETOP_VERSION}" > ${FILE} 
        rm -f ${FILE} 
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
}
if [ "${NETOP_COMBINED}" == true ];then
  combinedIPPoolCRD
  combinedNetworkCRD
else
  NetworkCRD
  IPPoolCRD
fi
