#!/bin/bash
source ${NETOP_ROOT_DIR}/global_ops_cfg.sh
cd ..
git clone https://github.com/Mellanox/nvidia-k8s-ipam.git
cd nvidia-k8s-ipam
git checkout network-operator-v${NETOP_VERSION}
cd deploy/crds
kubectl apply -f nv-ipam.nvidia.com_cidrpools.yaml,nv-ipam.nvidia.com_ippools.yaml
