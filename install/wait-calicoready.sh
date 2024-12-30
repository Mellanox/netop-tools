#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/install/readytest.sh
PODLIST=( 2,calico-apiserver,calico-apiserver 1,calico-system,calico-kube-controllers 1,calico-system,calico-node 1,calico-system,calico-typha 1,calico-system,csi-node-driver 1,kube-system,kube-apiserver 1,tigera-operator,tigera-operator 1,kube-system,kube-scheduler )
nsReady
