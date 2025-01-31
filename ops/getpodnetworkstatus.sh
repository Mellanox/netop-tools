#!/bin/bash
#
# https://github.com/Mellanox/nvidia-k8s-ipam?tab=readme-ov-file#configuration
# View network status of pod
#
NS=${1:-${NETOP_NAMESPACE}}
kubectl -n ${NS} get pods -o=custom-columns='NAME:metadata.name,NODE:spec.nodeName,NETWORK-STATUS:metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status'
