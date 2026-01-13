#!/bin/bash -e
#
# install network operator master node
#
set -euo pipefail  # Exit on error, undefined vars, pipe failures

if [ -z ${NETOP_ROOT_DIR} ];then
  echo "ERROR: Variable NETOP_ROOT_DIR is not set"
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
source ${NETOP_ROOT_DIR}/k8envroot.sh

CMD="${1}"
shift
case "${CMD}" in
master)
  systemctl mask swap.target # permanently turn off swap
  ${NETOP_ROOT_DIR}/install/ins-helm.sh
  ${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-k8repo.sh
  ${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-go.sh
  ${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-k8base.sh
  ${NETOP_ROOT_DIR}/install/${HOST_OS}/ins-docker.sh
  ;;
init)
  # Detect container runtime and configure appropriately
  source ${NETOP_ROOT_DIR}/install/detect_runtime.sh
  detect_container_runtime
  
  # Build kubeadm init command based on runtime and configuration
  KUBEADM_ARGS="--pod-network-cidr=${K8CIDR} --v=5"
  
  # Add CRI socket if needed (Docker with K8s 1.24+ or non-default runtime)
  if [ "${NEEDS_CRI_DOCKERD}" = "true" ] || [ "${CONTAINER_RUNTIME}" != "containerd" ]; then
    KUBEADM_ARGS="${KUBEADM_ARGS} --cri-socket=${CRI_SOCKET}"
  fi
  
  # Add server IP configuration if specified
  if [ "${K8SRVIP}" != "" ]; then
    KUBEADM_ARGS="${KUBEADM_ARGS} --apiserver-advertise-address=${K8SRVIP} --apiserver-cert-extra-sans=${K8SRVIP}"
  fi
  
  echo "Initializing Kubernetes with runtime: ${CONTAINER_RUNTIME}"
  echo "kubeadm init ${KUBEADM_ARGS}"
  
  # Run kubeadm init
  if ! kubeadm init ${KUBEADM_ARGS}; then
    echo "ERROR: kubeadm init failed"
    exit 1
  fi
  
  # Verify initialization was successful
  if [ ! -f /etc/kubernetes/admin.conf ]; then
    echo "ERROR: Kubernetes admin config not created - initialization may have failed"
    exit 1
  fi
  
  # ./fixes/fix config issues
  if ! ${NETOP_ROOT_DIR}/install/fixes/fixcrtauth.sh; then
    echo "ERROR: Failed to fix certificate auth configuration"
    exit 1
  fi
  
  if ! ${NETOP_ROOT_DIR}/install/fixes/fixcontainerd.sh; then
    echo "ERROR: Failed to configure container runtime"
    exit 1
  fi
  
  if ! ${NETOP_ROOT_DIR}/install/configcrictl.sh; then
    echo "ERROR: Failed to configure crictl"
    exit 1
  fi
  
  echo "Kubernetes master initialization completed successfully with ${CONTAINER_RUNTIME}"
  #./ins-multus.sh
  ;;
calico)
  ${NETOP_ROOT_DIR}/install/wait-k8sready.sh
  ${NETOP_ROOT_DIR}/install/ins-calico.sh
  ${NETOP_ROOT_DIR}/install/ins-calicoctl.sh
  ;;
netop)
  ${NETOP_ROOT_DIR}/install/wait-calicoready.sh
  # setup helm charts
  ${NETOP_ROOT_DIR}/install/ins-netop-chart.sh
  ${NETOP_ROOT_DIR}/install/ins-network-operator.sh
  ;;
app)
  #
  # deploy app
  #
  if [ "${1}" = "" ];then
    echo "error:missing appname:${1}"
    echo "install app usage:$0 app {APPNAME}"
    exit 1
  fi
  ./insapp.sh ${1}
  ;;
worker)
  if [ "${1}" = "" ];then
    echo "error:missing worker node:${1}"
    echo "install work usage:$0 worker {NODENAME}"
    exit 1
  fi
  # install a node, apply a label to the node
  ${NETOP_ROOT_DIR}/ops/labelworker.sh ${1}
  ;;
debug)
  # debug tools
  ./inskubectx.sh
  ./insnerdctl.sh
  ;;
*)
  echo "error:unknown command:${CMD}"
  echo "install master node usage:$0 master"
  echo "install worker node label usage:$0 worker {WORKERNODE}"
  echo "install sriov setup  usage:$0 sriov"
  echo "install app usage:$0 app {APPNAME}"
  exit 1
  ;;
esac
