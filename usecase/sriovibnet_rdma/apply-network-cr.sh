#!/bin/bash -x
#
# setup the host networks, and make the ip pool
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function applyNetworkCRDs()
{
  for NETOP_SU in ${NETOP_SULIST[@]};do
    for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
      for NIDXDEF in ${NETOP_NETLIST[@]};do
        NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
        FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}-cr.yaml"
        if [ -f ${FILE} ];then
          kubectl apply -f "${FILE}"
        else
          echo "ERROR:${FILE} not found"
        fi
      done
    done
  done
}
#
# make sure the ip pool is created
#
function applyIPAM_CRDs()
{
  if [ "${IPAM_TYPE}" = "nv-ipam" ];then
    for NETOP_SU in ${NETOP_SULIST[@]};do
      for NIDXDEF in ${NETOP_NETLIST[@]};do
        NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
        case "${NVIPAM_POOL_TYPE}" in
        IPPool)
          FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool-${NIDX}-${NETOP_SU}.yaml"
          ;;
        CIDRPool)
          FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/cidrpool-${NIDX}-${NETOP_SU}.yaml"
          ;;
        esac
        if [ -f ${FILE} ];then
          kubectl apply -f "${FILE}"
        else
          echo "ERROR:${FILE} not found"
        fi
      done
    done
  fi
}
function applySriovNodePolicy()
{
  for NIDXDEF in ${NETOP_NETLIST[@]};do
    NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
    FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/sriov-node-policy-${NIDX}.yaml"
    if [ -f ${FILE} ];then
      kubectl apply -f "${FILE}"
    else
      echo "ERROR:${FILE} not found"
    fi
# according to Ivan,
# Network-Attachment-Definition generated automatically, except for ib-sriov-cni and pkey
#   ${NETOP_ROOT_DIR}/ops/mk-sriovibnet-network-attachment.sh ${NIDX}
#   kubectl apply set-last-applied -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml" --create-annotation
#   kubectl apply -f "${DIR}/Network-Attachment-Definitions-${NIDX}.yaml"
  done
}
case ${NETOP_NETWORK_TYPE} in
SriovNetwork|SriovIBNetwork)
  applySriovNodePolicy
  ;;
esac 
applyIPAM_CRDs
applyNetworkCRDs
#
# verify the network devices
#
kubectl get ${NETOP_NETWORK_TYPE}
${NETOP_ROOT_DIR}/ops/getnetwork.sh
