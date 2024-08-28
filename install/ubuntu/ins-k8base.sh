#!/bin/bash -x
#
# Update the apt package index and install packages needed to use the Kubernetes apt repository:
#
source ./netop.cfg
apt-get update
apt-get install -y git
apt-get install -y apt-transport-https ca-certificates curl apt-utils
apt-get install -y openssh-server vim
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
# Update apt package index with the new repository and install kubectl:
#
apt-get update
#
# netork tools
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
--disableexcludes=kubernetes
fi
#
# get from docker repo, not from ubuntu defaults
#
#apt-get install -y containerd
#
# apt install -y podman-docker
# We are using containerd, not podman
#
apt-get install -y kubectl kubelet kubeadm jq
#
# install default plugins
#
PLUGINS="cni-plugins-linux-amd64-v0.8.6.tgz"
mkdir -p /opt/cni/bin
pushd .
cd /opt/cni/bin
curl -L --insecure -O https://github.com/containernetworking/plugins/releases/download/v0.8.6/${PLUGINS}
tar -xvf ./${PLUGINS}
popd
#
# config details here:
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
#
systemctl enable --now kubelet
systemctl disable ufw
systemctl stop ufw
#
rm -f /etc/containerd/config.toml
systemctl restart containerd
swapoff -a
#
# install go
#
apt install -y golang-go
#
#
#
apt autoremove
