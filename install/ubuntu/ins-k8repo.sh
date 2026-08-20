#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

function gpgkeys()
{
  mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8SVER}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8SVER}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  chmod 644 /etc/apt/sources.list.d/kubernetes.list
}
#
# SELinux permissive mode is used only when this Ubuntu host has SELinux
# configured. Kubernetes CNIs, kube-proxy, and container runtimes need to
# manage host networking state; enforcing SELinux without Kubernetes-specific
# policy can block those operations. Compensating controls should include
# Calico NetworkPolicy for pod traffic and host/perimeter firewall rules.
# Prefer targeted Kubernetes SELinux policy on hardened hosts instead of this
# permissive fallback.
#
function disable_selinux()
{
if [ -f /etc/selinux/config ];then
  echo "WARNING: Setting SELinux to permissive for Kubernetes/CNI host networking compatibility."
  echo "WARNING: Use Calico NetworkPolicy and host/perimeter firewall controls as compensating controls."
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
# Update apt package index with the new repository and install ${K8CL}:
#
apt-get update
#
# network tools
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
# https://kubernetes.io/docs/tasks/tools/install-${K8CL}-linux/
#
systemctl enable --now kubelet
#
rm -f /etc/containerd/config.toml
echo "Restarting containerd..."
if ! systemctl restart containerd; then
    echo "ERROR: Failed to restart containerd"
    exit 1
fi
swapoff -a
apt-get update
