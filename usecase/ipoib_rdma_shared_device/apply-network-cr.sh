#!/bin/bash
#
# setup the host networks, define the ip  pool
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

for NIDXDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
  NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NIDX}-cr.yaml"
  kubectl apply -f "${FILE}"
done
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
