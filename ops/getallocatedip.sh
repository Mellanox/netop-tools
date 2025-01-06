#!/bin/bash
#
# https://github.com/Mellanox/nvidia-k8s-ipam?tab=readme-ov-file#configuration
# View allocated IP Blocks for a node from IPPool
#
kubectl get ippools.nv-ipam.nvidia.com -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"} {range .status.allocations[*]}{"\t"}{.nodeName} => Start IP: {.startIP} End IP: {.endIP}{"\n"}{end}{"\n"}{end}'
