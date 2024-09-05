#!/bin/bash -x
#
#
function gpgkeys()
{
  mkdir -p /etc/apt/keyrings
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
}
#
# Set SELinux in permissive mode (effectively disabling it)
#
function disable_selinux()
{
if [ -d /etc/selinux/config ];then
  setenforce 0
  sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
fi
}
#
# Update the apt package index and install packages needed to use the Kubernetes apt repository:
#
apt-get update
apt-get install -y apt-transport-https ca-certificates curl
#gpgkeys done in other script
# Update apt package index with the new repository and install kubectl:
#
apt-get update
#
# netork tools
disable_selinux
#
apt install -y net-tools
#
#--disableexcludes=kubernetes
#
# get from docker repo, not from ubuntu defaults
#
apt-get install -y kubectl kubelet kubeadm jq
#
# config details here:
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
#
systemctl enable --now kubelet
#
rm -f /etc/containerd/config.toml
systemctl restart containerd
swapoff -a
apt-get update
