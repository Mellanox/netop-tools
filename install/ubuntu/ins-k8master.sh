#!/bin/bash
#
# install network operator master node
#
if [ -z ${NETOP_ROOT_DIR} ];then
  echo "NETOP_ROOT_DIR directory is not set"
  exit 1
fi

source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/k8envroot.sh

CMD="${1}"
shift
case "${CMD}" in
master)
  systemctl mask swap.target # permanently turn off swap
  apt-get install -y git
  ${NETOP_ROOT_DIR}/install/installhelm.sh
  ${NETOP_ROOT_DIR}/install/installk8repo.sh
  ${NETOP_ROOT_DIR}/install/installk8base.sh
  ${NETOP_ROOT_DIR}/install/installdocker.sh
  ;;
init)
  kubeadm init --pod-network-cidr=${K8CIDR}
  SRVIP="192.168.122.128"
  #kubeadm init --apiserver-advertise-address="${SRVIP} --apiserver-cert-extra-sans="${SRVIP} --node-name ub2204-master --pod-network-cidr=${K8CIDR}
  #kubeadm init --apiserver-advertise-address="${SRVIP}" --apiserver-cert-extra-sans="${SRVIP}" --pod-network-cidr=${K8CIDR}
  # fix config issues
  ${NETOP_ROOT_DIR}/install/fixcrtauth.sh
  ${NETOP_ROOT_DIR}/install/fixcontainerd.sh 
  ${NETOP_ROOT_DIR}/install/configcrictl.sh
  #./installmultus.sh
  ;;
calico)
  # will need a wait here.
  ${NETOP_ROOT_DIR}/install/installcalico.sh
  ;;
netop)
  # network operator needs calico
  ${NETOP_ROOT_DIR}/install/install-network-operator.sh
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
  ./installapp.sh ${1}
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
  ./installkubectx.sh
  ./installnerdctl.sh
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
