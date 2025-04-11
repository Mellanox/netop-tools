#!/bin/bash
#
# https://github.com/Mellanox/nvidia-k8s-ipam?tab=readme-ov-file#configuration
# View network status of pod
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
NS=${1:-${NETOP_NAMESPACE}}
${K8CL} -n ${NS} get pods -o=custom-columns='NAME:metadata.name,NODE:spec.nodeName,NETWORK-STATUS:metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status'
