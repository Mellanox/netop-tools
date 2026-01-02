#!/bin/bash -e
#
# install network operator master node
#

if [ -z ${NETOP_ROOT_DIR} ];then
  echo "Variable NETOP_ROOT_DIR is not set"
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
  if [ "${K8SRVIP}" = "" ];then
    kubeadm init --pod-network-cidr=${K8CIDR} --v=5
  else
    #kubeadm init --apiserver-advertise-address="${K8SRVIP} --apiserver-cert-extra-sans="${K8SRVIP} --node-name ub2204-master --pod-network-cidr=${K8CIDR}
    kubeadm init --apiserver-advertise-address="${K8SRVIP}" --apiserver-cert-extra-sans="${K8SRVIP}" --pod-network-cidr=${K8CIDR} --v=5
  fi
  # ./fixes/fix config issues
  ${NETOP_ROOT_DIR}/install/fixes/fixcrtauth.sh
  ${NETOP_ROOT_DIR}/install/fixes/fixcontainerd.sh 
  ${NETOP_ROOT_DIR}/install/configcrictl.sh
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
