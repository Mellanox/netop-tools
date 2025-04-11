#!/bin/bash
#
#
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"
function keyring2004old()
{
  source /etc/os-release
  if [ "${PRETTY_NAME}" = "Ubuntu 20.04 LTS" ];then
    mkdir -p /etc/apt/keyrings
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
  fi
}
# Download the public signing key for the Kubernetes package repositories.
# The same signing key is used for all repositories so you can disregard the version in the URL:
function keyring2004()
{
  # If the folder `/etc/apt/keyrings` does not exist, it should be created before the curl command, read the note below.
  mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8SVER}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring
  #Note:
  #In releases older than Debian 12 and Ubuntu 22.04, folder /etc/apt/keyrings does not exist by default, and it should be created before the curl command.
  #Add the appropriate Kubernetes apt repository. If you want to use Kubernetes version different than v1.31, replace v1.31 with the desired minor version in the command below:
  #
  # This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v'${K8SVER}'/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
  chmod 644 /etc/apt/sources.list.d/kubernetes.list   # helps tools such as command-not-found to work correctly
}
apt-get update -y
# apt-transport-https may be a dummy package; if so, you can skip that package
apt-get install -y apt-transport-https ca-certificates curl gnupg
keyring2004
#Note:
#To upgrade ${K8CL} to another minor release, you'll need to bump the version in /etc/apt/sources.list.d/kubernetes.list before running apt-get update and apt-get upgrade. This procedure is described in more detail in Changing The Kubernetes Package Repository.
# Update apt package index, then install ${K8CL}:

apt-get update -y
apt-get install -y ${K8CL} kubelet kubeadm jq
