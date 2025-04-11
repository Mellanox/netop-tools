#!/bin/bash
#
# role back ipam
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} delete -f ./ipam/nv-ipam.yaml
${K8CL} delete -f ./ipam/ippool.yaml
rm -f /etc/cni/net.d/nv-ipam.d/10-${NETOP_NETWORK}.conf
