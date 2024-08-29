#!/bin/bash -x
#
# install k8 master for first time
#
source ./netop.cfg
./restart/removek8master.sh
cd ./install
./ins-k8master.sh master
./ins-k8master.sh init
./ins-k8master.sh calico
./ins-k8master.sh netop
kubectl get nodes
