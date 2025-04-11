#!/bin/bash
#
# https://github.com/Mellanox/nvidia-k8s-ipam?tab=readme-ov-file#configuration
source ${NETOP_ROOT_DIR}/global_ops.cfg
# View allocated IP Prefixes for a node from CIDRPool
#
${K8CL} get cidrpools.nv-ipam.nvidia.com -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"} {range .status.allocations[*]}{"\t"}{.nodeName} => Prefix: {.prefix} Gateway: {.gateway}{"\n"}{end}{"\n"}{end}'
