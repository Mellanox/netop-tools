#!/bin/bash
#
# config details here:
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
#
function restart()
{
  systemctl enable --now kubelet
  systemctl disable ufw
  systemctl stop ufw
  #
  rm -f /etc/containerd/config.toml
  systemctl restart containerd
  ${NETOP_ROOT_DIR}/install/fixes/fixcontainerd.sh
  swapoff -a
}
restart
