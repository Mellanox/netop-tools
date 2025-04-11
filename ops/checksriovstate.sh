#!/bin/bash
#
# get the SriovNetworkNodePolicy
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} get -n ${NETOP_NAMESPACE} sriovnetworknodestate -o yaml
