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
cmdIPAM_CRDs apply
cmdNetworkCRDs apply
#
# verify the network devices
#
${docmd} ${K8CL} get ${NETOP_NETWORK_TYPE}
${NETOP_ROOT_DIR}/ops/getnetwork.sh
