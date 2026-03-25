#!/bin/bash
#
# On control plane
#

function containerd()
{
  # Generate default config
  containerd config default | tee /etc/containerd/config.toml
  
  # Enable systemd cgroup driver
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  
  # Restart containerd
  echo "Restarting containerd..."
  if ! systemctl restart containerd; then
    echo "ERROR: Failed to restart containerd"
    exit 1
  fi
}
# Reset current cluster
kubeadm reset -f

# Clean up
rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet /etc/kubernetes
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
containerd

# Disable swap
swapoff -a

# Initialize fresh with v1.34
kubeadm init --pod-network-cidr=10.244.0.0/16 --v=5

# Setup kubeconfig
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (Calico)
# Use version from global configuration
source "${NETOP_ROOT_DIR:-/opt/netop-tools}/global_ops.cfg" 2>/dev/null || true
CALICO_VERSION="${CALICO_VERSION:-v3.28.2}"
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"

# Verify
kubectl get nodes
kubectl version
