#!/bin/bash
#
#
#
# firewalld can conflict with Kubernetes-managed iptables/nftables rules used by
# kube-proxy, container runtimes, and Calico. Stopping it keeps pod/service
# networking functional, but weakens host firewall posture. Use Calico
# NetworkPolicy for pod traffic and enforce required node-level policy with
# host/perimeter firewalls or Kubernetes-aware firewall rules.
#
echo "WARNING: Stopping firewalld for Kubernetes-managed networking compatibility."
echo "WARNING: Use Calico NetworkPolicy and host/perimeter firewall controls as compensating controls."
systemctl stop firewalld
