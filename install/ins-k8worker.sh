#!/bin/bash
#
# install a network operator worker node
#
if [ -z ${NETOP_ROOT_DIR} ];then
    echo "NETOP_ROOT_DIR is not set"
    exit 1
fi

source ${NETOP_ROOT_DIR}/global_ops.cfg

${NETOP_ROOT_DIR}/install/ins-helm.sh 
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-k8repo.sh
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-go.sh
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-k8base.sh
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-docker.sh 
${NETOP_ROOT_DIR}/install/fixes/fixcrtauth.sh
${NETOP_ROOT_DIR}/install/fixes/fixcontainerd.sh
${NETOP_ROOT_DIR}/install/configcrictl.sh
${NETOP_ROOT_DIR}/install/ins-nerdctl.sh
systemctl mask swap.target # permanently turn off swap
#./check_rdma.sh
${NETOP_ROOT_DIR}/ops/reconnectworker.sh 
cat << HERE_DOC
on the master node you need to run ./joincluster.sh to get the join command like below
#kubeadm join 10.7.12.85:6443 --token 6ahdt3.in48hi1fdldxclsn --discovery-token-ca-cert-hash sha256:f9ff7af084010f44ab145eb212111da24d695c65de85af7381188f2987a06178
copy the command and run from worker node. this could be a script
then from the master node add the label.
${NETOP_ROOT_DIR}/ops/labelworker.sh {WORKERNODE}
HERE_DOC
