#!/bin/bash
#
# delete the 2ndary networks, ip pools, sriov policy files
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
source ${NETOP_ROOT_DIR}/ops/cmd-network-cr.sh
cmdNetworkCRDs delete
cmdIPAM_CRDs delete
case ${NETOP_NETWORK_TYPE} in
SriovNetwork|SriovIBNetwork)
  cmdSriovNodePolicy delete
  ;;
esac 
