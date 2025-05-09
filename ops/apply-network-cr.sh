#!/bin/bash
#
# create the 2ndary networks, ip pools, sriov policy files
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
source ${NETOP_ROOT_DIR}/ops/cmd-network-cr.sh
case ${NETOP_NETWORK_TYPE} in
SriovNetwork|SriovIBNetwork)
  cmdSriovNodePolicy apply
  ;;
esac 
cmdNetworkCRDs apply
sleep 5
cmdIPAM_CRDs apply
#
# verify the network devices
#

if [ "${CREATE_CONFIG_ONLY}" != "1" ];then
  ${K8CL} get ${NETOP_NETWORK_TYPE}
  ${NETOP_ROOT_DIR}/ops/getnetwork.sh
fi
