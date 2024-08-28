#!/bin/bash -x
#
# install network operator master node
#
source ./netop.cfg
CMD="${1}"
shift
case "${CMD}" in
master)
  systemctl mask swap.target # permanently turn off swap
  apt-get install -y git
  ./installhelm.sh
  ./installk8repo.sh
  ./installk8base.sh
  ./installdocker.sh
  ;;
init)
  kubeadm init --pod-network-cidr=${K8CIDR}
  SRVIP="192.168.122.128"
  #kubeadm init --apiserver-advertise-address="${SRVIP} --apiserver-cert-extra-sans="${SRVIP} --node-name ub2204-master --pod-network-cidr=${K8CIDR}
  #kubeadm init --apiserver-advertise-address="${SRVIP}" --apiserver-cert-extra-sans="${SRVIP}" --pod-network-cidr=${K8CIDR}
  # fix config issues
  source ../k8envroot.sh
  ./fixcrtauth.sh
  ./fixcontainerd.sh 
  ./configcrictl.sh
  #./installmultus.sh
  ;;
calico)
  source ../k8envroot.sh
  # will need a wait here.
  ./installcalico.sh
  ;;
netop)
  source ../k8envroot.sh
  # network operator needs calico
  ./install-network-operator.sh
  ;;
app)
  source ../k8envroot.sh
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
  ./ops/labelworker.sh ${1}
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
