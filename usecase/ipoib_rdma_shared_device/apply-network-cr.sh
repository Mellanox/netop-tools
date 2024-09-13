#!/bin/bash
#
# setup the host networks, define the ip  pool
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

for NIDXDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
  NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
  ${NETOP_ROOT_DIR}/ops/mk-ipoib-ipam-cr.sh ${NDEV} ${NIDX}
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NIDX}-cr.yaml"
  kubectl apply -f "${FILE}"
done
#
# make sure the ip pool is created
#
kubectl get ${NETOP_NETWORK_TYPE}
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  ${NETOP_ROOT_DIR}/ops/mk-nvipam-pool.sh
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool.yaml"
  kubectl apply -f "${FILE}"
fi
#
# verify the network devices
#
${NETOP_ROOT_DIR}/ops/getnetwork.sh
