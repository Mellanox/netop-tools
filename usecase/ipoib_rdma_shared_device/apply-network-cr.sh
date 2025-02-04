#!/bin/bash
#
# setup the host networks, define the ip  pool
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

for NETOP_SU in ${NETOP_SULIST[@]};do
  for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
    for NIDXDEF in ${NETOP_NETLIST[@]};do
      NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
      NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
      FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}-cr.yaml"
      if [ -f ${FILE} ];then
        kubectl apply -f "${FILE}"
      else
        echo "ERROR:${FILE} not found"
      fi
    done
  done
done
#
# make sure the ip pool is created
#
kubectl get ${NETOP_NETWORK_TYPE}
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  for NETOP_SU in ${NETOP_SULIST[@]};do
    for NIDXDEF in ${NETOP_NETLIST[@]};do
      NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
      case "${IPAM_POOL_TYPE}" in
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
#
# verify the network devices
#
${NETOP_ROOT_DIR}/ops/getnetwork.sh
#
# make sure the ip pool is created
#
kubectl get ${NETOP_NETWORK_TYPE}
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool.yaml"
  kubectl apply -f "${FILE}"
fi
#
# verify the network devices
#
${NETOP_ROOT_DIR}/ops/getnetwork.sh
