#!/bin/bash
#
# install a network operator worker node
#
./ins-helm.sh 
./ins-k8repo.sh
./ins-go.sh
./ins-k8base.sh
./ins-docker.sh 
./fixes/fixcrtauth.sh
./fixes/fixcontainerd.sh
./configcrictl.sh
./insnerdctl.sh
systemctl mask swap.target # permanently turn off swap
./check_rdma.sh
./reconnectworker.sh 
cat << HERE_DOC
on the master node you need to run ./joincluster.sh to get the join command like below
#kubeadm join 10.7.12.85:6443 --token 6ahdt3.in48hi1fdldxclsn --discovery-token-ca-cert-hash sha256:f9ff7af084010f44ab145eb212111da24d695c65de85af7381188f2987a06178
copy the command and run from worker node. this could be a script
then from the master node add the label.
./ops/labelworker.sh {WORKERNODE}
HERE_DOC
