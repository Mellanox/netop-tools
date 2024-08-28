#!/bin/bash -x
#
# install packages needed to use the Kubernetes repository:
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management
#
# install default plugins
#
function cni()
{
  PLUGINS="cni-plugins-linux-amd64-v0.8.6.tgz"
  mkdir -p /opt/cni/bin
  pushd .
  cd /opt/cni/bin
  curl -L --insecure -O https://github.com/containernetworking/plugins/releases/download/v0.8.6/${PLUGINS}
  tar -xvf ./${PLUGINS}
  popd
}
# Set SELinux in permissive mode (effectively disabling it)
#
function disable_selinux()
{
if [ -f "/etc/selinux/config" ];then
  setenforce 0
  sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
#
fi
}
function setup_repo()
{
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
EOF
}
disable_selinux
dnf update
dnf install -y openssh-server vim git
#
# netork tools
#
dnf install -y net-tools lldpd jq
systemctl enable lldpd
systemctl start lldpd
lldpcli show neighbors
#
#
setup_repo
dnf install -y kubectl kubelet kubeadm --disableexcludes=kubernetes
#
# config details here:
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
#
systemctl enable --now kubelet
#systemctl disable ufw
#systemctl stop ufw
#
rm -f /etc/containerd/config.toml
systemctl restart containerd
swapoff -a
