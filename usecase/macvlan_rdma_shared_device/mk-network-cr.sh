#!/bin/bash
#
# setup the host networks, define the ip  pool
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/mk-network-ippool-cr.sh

for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
  for NIDXDEF in ${NETOP_NETLIST[@]};do
    NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
    NDEV=`echo ${NIDXDEF}|cut -d',' -f4`
    FILE=$( ${NETOP_ROOT_DIR}/ops/mk-macvlan-ipam-cr.sh ${NDEV} ${NIDX} ${NETOP_APP_NAMESPACE} )
    echo ${FILE}
  done
done
mkNetworkIPPoolCRDs
