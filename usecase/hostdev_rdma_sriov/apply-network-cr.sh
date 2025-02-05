#!/bin/bash
#
# setup the host networks, define the ip  pool
#
# you'll need to define the VFs on thw orker nodes
# echo 0 > /sys/devices/pci0000:20/0000:20:01.5/0000:23:00.0/sriov_numvfs
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

for NETOP_SU in ${NETOP_SULIST[@]};do
  for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
    for NIDXDEF in ${NETOP_NETLIST[@]};do
      NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
      FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}-cr.yaml"
      kubectl apply -f "${FILE}"
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
      case "${NVIPAM_POOL_TYPE}" in
      IPPool)
        FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool-${NIDX}-${NETOP_SU}.yaml"
        ;;
      CIDRPool)
        FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/cidrpool-${NIDX}-${NETOP_SU}.yaml"
        ;;
      esac
      kubectl apply -f "${FILE}"
    done
  done
fi
#
# verify the network devices
#
${NETOP_ROOT_DIR}/ops/getnetwork.sh
