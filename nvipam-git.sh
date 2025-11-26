#!/bin/bash
cd ..
git clone https://github.com/Mellanox/nvidia-k8s-ipam.git
cd nvidia-k8s-ipam
git checkout ${1}
cd deploy/crds
kubectl apply -f nv-ipam.nvidia.com_cidrpools.yaml,nv-ipam.nvidia.com_ippools.yaml
