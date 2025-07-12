#!/bin/bash
#
# get the connection info for static arp settings
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
SRVR=${1}
shift
CLNT=${1}
shift
for NET_DEV in ${*};do
  MAC_ADDR=$( ${K8CL} exec ${SRVR} -- bash -c "ip link show ${NET_DEV} | grep link | tr -s [:space:] | cut -d' ' -f3" )
  IP=$( ${K8CL} exec ${SRVR} -- bash -c "ip -br a show ${NET_DEV} | tr -s [:space:] | cut -d' ' -f3| cut -d'/' -f1" )
  echo ${K8CL} exec ${CLNT} -- bash -c "arp -i ${NET_DEV} -s ${IP} ${MAC_ADDR}"
  ${K8CL} exec ${CLNT} -- bash -c "ip -s -s neigh flush all;arp -i ${NET_DEV} -s ${IP} ${MAC_ADDR};arp" |grep "${IP}"
done
