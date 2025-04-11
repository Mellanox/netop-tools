#!/bin/bash
#
# restart k8 master
#
source ./removek8master.sh
function restartk8()
{
  # Bootstrap K8s cluster via kubeadm:
  systemctl enable docker
  systemctl enable kubelet
  systemctl daemon-reload
  netstat -lnp | grep ":10250"
}
restartk8
