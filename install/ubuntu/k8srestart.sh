#!/bin/bash
#
# config details here:
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function restart()
{
  systemctl enable --now kubelet
  # UFW can conflict with Kubernetes-managed iptables/nftables rules used by
  # kube-proxy, container runtimes, and Calico. Disabling it keeps pod/service
  # networking functional, but weakens host firewall posture. Use Calico
  # NetworkPolicy for pod traffic and enforce required node-level policy with
  # host/perimeter firewalls or Kubernetes-aware firewall rules.
  echo "WARNING: Disabling UFW for Kubernetes-managed networking compatibility."
  echo "WARNING: Use Calico NetworkPolicy and host/perimeter firewall controls as compensating controls."
  systemctl disable ufw 2>/dev/null || true  # UFW may not be installed
  systemctl stop ufw 2>/dev/null || true
  
  # Configure container runtime properly (this handles both containerd and docker)
  ${NETOP_ROOT_DIR}/install/fixes/fixcontainerd.sh
  
  # Disable swap permanently
  swapoff -a
  
  # Make sure swap is disabled in fstab
  sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab 2>/dev/null || true
}
restart
