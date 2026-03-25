#!/bin/bash
#
# Update the apt package index and install packages needed to use the Kubernetes apt repository:
#
set -euo pipefail  # Exit on error, undefined vars, pipe failures

if [ -z ${NETOP_ROOT_DIR} ];then
    echo "ERROR: NETOP_ROOT_DIR is not set"
    exit 1
fi

source ${NETOP_ROOT_DIR}/global_ops.cfg

# Validate required variables
if [ -z "${K8SVER}" ]; then
    echo "ERROR: K8SVER is not set in global configuration"
    exit 1
fi

if [ -z "${K8CL}" ]; then
    echo "ERROR: K8CL is not set in global configuration"
    exit 1
fi

apt-get update

apt-get install -y \
apt-transport-https \
git \
ca-certificates \
curl apt-utils \
openssh-server vim
#
# Download the Google Cloud public signing key:
#
function keyring_old()
{
  curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
  #
  # Add the Kubernetes apt repository:
  #
  echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
}
#Download the public signing key for the Kubernetes package repositories. The same signing key is used for all repositories so you can disregard the version in the URL:
function keyring2204()
{
  # If the folder `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
  mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8SVER}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
  #Note:
  #In releases older than Debian 12 and Ubuntu 22.04, folder /etc/apt/keyrings does not exist by default, and it should be created before the curl command.
  #Add the appropriate Kubernetes apt repository. If you want to use Kubernetes version different than v${K8SVER}, replace v${K8SVER} with the desired minor version in the command below:
  #
  # This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v'${K8SVER}'/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
}
keyring2204
#
# Update apt package index with the new repository and install ${K8CL}:
#
apt-get update
#
# network tools
#
apt install -y net-tools lldpd
lldpcli show neighbors
#
#
if [ -f "/etc/selinux/config" ];then
#
# Set SELinux in permissive mode (effectively disabling it)
#
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
#
fi
#
# get from docker repo, not from ubuntu defaults
#
#apt-get install -y containerd
#
# apt install -y podman-docker
# We are using containerd, not podman
#
apt-get install -y ${K8CL} kubelet kubeadm jq
#
# install default plugins
#
PLUGINS="cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz"
[ ! -d /opt/cni/bin ] && mkdir -p /opt/cni/bin
curl -L --insecure -o - https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/${PLUGINS} | tar xfz - -C /opt/cni/bin

#
# install go
#
apt install -y golang-go
apt autoremove
#
# run restart code
#
${NETOP_ROOT_DIR}/install/${HOST_OS}/k8srestart.sh
