#!/bin/bash
#
# role back ipam
#
source ./netop.cfg
kubectl delete -f ./ipam/nv-ipam.yaml
kubectl delete -f ./ipam/ippool.yaml
rm -f /etc/cni/net.d/nv-ipam.d/10-${NETOP_NETWORK}.conf
