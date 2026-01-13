#!/bin/bash
#
# install a network operator worker node
#
set -euo pipefail  # Exit on error, undefined vars, pipe failures

if [ -z ${NETOP_ROOT_DIR} ];then
    echo "ERROR: NETOP_ROOT_DIR is not set"
    exit 1
fi

# Validate environment
if [ ! -d "${NETOP_ROOT_DIR}" ]; then
    echo "ERROR: NETOP_ROOT_DIR directory does not exist: ${NETOP_ROOT_DIR}"
    exit 1
fi

if [ ! -f "${NETOP_ROOT_DIR}/global_ops.cfg" ]; then
    echo "ERROR: Configuration file not found: ${NETOP_ROOT_DIR}/global_ops.cfg"
    exit 1
fi

source ${NETOP_ROOT_DIR}/global_ops.cfg

${NETOP_ROOT_DIR}/install/ins-helm.sh 
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-k8repo.sh
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-go.sh
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-k8base.sh
${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-docker.sh 
# Configure container runtime first
${NETOP_ROOT_DIR}/install/fixes/fixcrtauth.sh
${NETOP_ROOT_DIR}/install/fixes/fixcontainerd.sh
${NETOP_ROOT_DIR}/install/configcrictl.sh
${NETOP_ROOT_DIR}/install/ins-nerdctl.sh
systemctl mask swap.target # permanently turn off swap

# Display runtime information for worker join
source ${NETOP_ROOT_DIR}/install/detect_runtime.sh
detect_container_runtime
echo "Worker node configured with container runtime: ${CONTAINER_RUNTIME}"
if [ "${NEEDS_CRI_DOCKERD}" = "true" ]; then
  echo "NOTE: When joining this worker to the cluster, use CRI socket: ${CRI_SOCKET}"
  echo "Example join command should include: --cri-socket=${CRI_SOCKET}"
fi
#./check_rdma.sh
${NETOP_ROOT_DIR}/ops/reconnectworker.sh 
cat << HERE_DOC
on the master node you need to run ./joincluster.sh to get the join command like below
#kubeadm join 10.7.12.85:6443 --token 6ahdt3.in48hi1fdldxclsn --discovery-token-ca-cert-hash sha256:f9ff7af084010f44ab145eb212111da24d695c65de85af7381188f2987a06178
copy the command and run from worker node. this could be a script
then from the master node add the label.
${NETOP_ROOT_DIR}/ops/labelworker.sh {WORKERNODE}
HERE_DOC
