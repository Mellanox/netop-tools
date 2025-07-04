#!/bin/bash
#
# setup the host networks, define the ip  pool
#
# For HostDeviceNetwork you'll need to define the SRIOV VFs on the worker nodes
# echo 0 > /sys/devices/pci0000:20/0000:20:01.5/0000:23:00.0/sriov_numvfs
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function mkIPPoolCRDs()
{
  SUBNET_FILE="/tmp/subnets.$$"
  if [ "${IPAM_TYPE}" = "nv-ipam" ];then
    for NETOP_SU in ${NETOP_SULIST[@]};do
      #echo "NETOP_SU:${NETOP_SU}"
      IPPOOLS_KEY=NETOP_IPPOOLS[${NETOP_SU}]
      for IPPOOL_KEY in ${IPPOOLS_KEY[@]};do
        #echo "IPPOOL_KEY:${IPPOOL_KEY}"
        IPPOOL=${!IPPOOL_KEY}
        #echo "IPPOOL:${IPPOOL}"
        NUM_SUBNETS="${#NETOP_NETLIST[@]}"
        ${NETOP_ROOT_DIR}/ops/generate_subnets.sh "${NETOP_NETWORK_RANGE}" "${NUM_SUBNETS}" ${NETOP_NETWORK_GW} > ${SUBNET_FILE}
        LINENUM=1
        for NIDXDEF in ${NETOP_NETLIST[@]};do
          NIDX=$(echo ${NIDXDEF}|cut -d',' -f1)
          LINE=$(sed -n ${LINENUMNUM}p ${SUBNET_FILE})
          RANGE=$(echo ${LINE}|cut -d' ' -f1)
          GW=$(echo ${LINE}|cut -d' ' -f3)
          case "${NVIPAM_POOL_TYPE}" in
          IPPool)
            FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool-${NIDX}-${NETOP_SU}.yaml"
            ${NETOP_ROOT_DIR}/ops/mk-nvipam-pool.sh "${FILE}" "${NIDX}" "${NETOP_SU}" "${RANGE}" "${GW}" "${NETOP_PERNODE_BLOCKSIZE}"
            ;;
          CIDRPool)
            FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/cidrpool-${NIDX}-${NETOP_SU}.yaml"
            ${NETOP_ROOT_DIR}/ops/mk-nvipam-cidr.sh "${FILE}" "${NIDX}" "${NETOP_SU}" "${RANGE}" "${GW}" "${NETOP_PERNODE_BLOCKSIZE}"
            ;;
          esac
          LINENUM=let LINENUM+1
          echo ${FILE}
        done
        rm  ${SUBNET_FILE}
      done
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
for NETOP_SU in ${NETOP_SULIST[@]};do
  for NIDXDEF in ${NETOP_NETLIST[@]};do
    NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
    NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
    case ${NETOP_NETWORK_TYPE} in
    SriovIBNetwork)
      FILE=$( ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-node-policy.sh ${NIDX} ${NDEV} ${NETOP_SU})
      ;;
    SriovNetwork)
      FILE=$( ${NETOP_ROOT_DIR}/ops/mk-sriovnet-node-policy.sh ${NIDX} ${NDEV} ${NETOP_SU})
      ;;
    esac
    for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
      case ${NETOP_NETWORK_TYPE} in
      HostDeviceNetwork)
        FILE=$(${NETOP_ROOT_DIR}/ops/mk-hostdev-sriov-ipam-cr.sh ${NIDX} ${NETOP_SU} ${NETOP_APP_NAMESPACE})
        ;;
      IPoIBNetwork)
        FILE=$(${NETOP_ROOT_DIR}/ops/mk-ipoib-ipam-cr.sh ${NDEV} ${NIDX} ${NETOP_SU} ${NETOP_APP_NAMESPACE})
        ;;
      MacvlanNetwork)
        FILE=$( ${NETOP_ROOT_DIR}/ops/mk-hostdev-macvlan-ipam-cr.sh ${NDEV} ${NIDX} ${NETOP_SU} ${NETOP_APP_NAMESPACE} )
        ;;
      SriovNetwork|SriovIBNetwork)
        FILE=$( ${NETOP_ROOT_DIR}/ops/mk-sriovnet-ipam-cr.sh ${NIDX} ${NETOP_SU} ${NETOP_APP_NAMESPACE} )
        ;;
      esac
    done
  done
done
mkIPPoolCRDs
