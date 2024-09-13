#!/bin/bash -x
#
# rm k8 master
#
function removek8()
{
  kubeadm reset --force&
  crictl stop `crictl ps | egrep "calico|network-operator|kube" | cut -d' ' -f1`
  waitall
  systemctl stop docker
  systemctl stop containerd
  systemctl stop kubelet 
  rm -rf /etc/kubernetes/
  #rm -rf .kube/
  rm -rf /var/lib/kubelet/
  rm -rf /var/lib/cni/
  rm -rf /etc/cni/
  rm -rf /var/lib/etcd/
  rm -rf /etc/kubernetes/kubelet.conf /etc/kubernetes/pki/ca.crt
  swapoff -a

}
removek8
