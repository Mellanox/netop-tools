#!/bin/bash
#
# setup the host networks, define the ip  pool
#
# you'll need to define the VFs on thw orker nodes
# echo 0 > /sys/devices/pci0000:20/0000:20:01.5/0000:23:00.0/sriov_numvfs
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

for NIDXDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
  ${NETOP_ROOT_DIR}/ops/mk-hostdev-ipam-cr.sh ${NIDX}
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NIDX}-cr.yaml"
  echo ${FILE}
done
#
# make sure the ip pool is created
#
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  ${NETOP_ROOT_DIR}/ops/mk-nvipam-pool.sh
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool.yaml"
  echo ${FILE}
fi
