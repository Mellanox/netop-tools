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
  CNI_TMP_DIR=$(mktemp -d) || exit 1
  trap 'rm -rf "${CNI_TMP_DIR}"' RETURN
  curl -fL -o "${CNI_TMP_DIR}/${PLUGINS}" "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/${PLUGINS}" || exit 1
  curl -fL -o "${CNI_TMP_DIR}/${PLUGINS}.sha256" "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/${PLUGINS}.sha256" || exit 1
  EXPECTED_SHA256=$(awk '{print $1; exit}' "${CNI_TMP_DIR}/${PLUGINS}.sha256")
  if [ -z "${EXPECTED_SHA256}" ];then
    echo "ERROR: Missing SHA256 checksum for ${PLUGINS}"
    exit 1
  fi
  echo "${EXPECTED_SHA256}  ${CNI_TMP_DIR}/${PLUGINS}" | sha256sum -c - || exit 1
  [ ! -d /opt/cni/bin ] && mkdir -p /opt/cni/bin
  tar xfz "${CNI_TMP_DIR}/${PLUGINS}" -C /opt/cni/bin || exit 1
  popd
}
# SELinux permissive mode is used for Kubernetes/CNI host networking
# compatibility when no site-specific Kubernetes SELinux policy is installed.
# Kubernetes CNIs, kube-proxy, and container runtimes need to manage host
# networking state; enforcing SELinux without the right policy can block those
# operations. Compensating controls should include Calico NetworkPolicy for pod
# traffic and host/perimeter firewall rules. Prefer targeted Kubernetes SELinux
# policy on hardened hosts instead of this permissive fallback.
#
function disable_selinux()
{
if [ -f "/etc/selinux/config" ];then
  echo "WARNING: Setting SELinux to permissive for Kubernetes/CNI host networking compatibility."
  echo "WARNING: Use Calico NetworkPolicy and host/perimeter firewall controls as compensating controls."
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
