#!/bin/bash
#
# install packages needed to use the Kubernetes repository:
# https://kubernetes.io/docs/tasks/tools/install-${K8CL}-linux/#install-using-native-package-management
#
# install default plugins
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

function cni()
{
  PLUGINS="cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"
  [ ! -d /opt/cni/bin ] && mkdir -p /opt/cni/bin
  curl -L --insecure -o - https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/${PLUGINS} | tar xfz - -C /opt/cni/bin
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
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8SVER}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8SVER}/rpm/repodata/repomd.xml.key
EOF
}
disable_selinux
dnf update
dnf install -y openssh-server vim git
#
# network tools
#
dnf install -y net-tools lldpd jq
echo "Enabling and starting lldpd..."
if ! systemctl enable lldpd; then
    echo "ERROR: Failed to enable lldpd"
    exit 1
fi
if ! systemctl start lldpd; then
    echo "ERROR: Failed to start lldpd"
    exit 1
fi
lldpcli show neighbors
#
#
setup_repo
dnf install -y ${K8CL} kubelet kubeadm --disableexcludes=kubernetes
#
# config details here:
# https://kubernetes.io/docs/tasks/tools/install-${K8CL}-linux/
#
systemctl enable --now kubelet
#systemctl disable ufw
#systemctl stop ufw
#
rm -f /etc/containerd/config.toml
echo "Restarting containerd..."
if ! systemctl restart containerd; then
    echo "ERROR: Failed to restart containerd"
    exit 1
fi
swapoff -a
