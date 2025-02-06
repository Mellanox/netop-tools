#!/bin/bash
#
# setup the host networks, define the ip  pool
#
# you'll need to define the VFs on thw orker nodes
# echo 0 > /sys/devices/pci0000:20/0000:20:01.5/0000:23:00.0/sriov_numvfs
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/mk-network-ippool-cr.sh

for NETOP_SU in ${NETOP_SULIST[@]};do
  for NIDXDEF in ${NETOP_NETLIST[@]};do
    for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
      NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
      FILE=$(${NETOP_ROOT_DIR}/ops/mk-hostdev-sriov-ipam-cr.sh ${NIDX} ${NETOP_SU} ${NETOP_APP_NAMESPACE})
      echo ${FILE}
    done
  done
done
mkNetworkIPPoolCRDs
