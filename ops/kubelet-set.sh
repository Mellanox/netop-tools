#!/bin/bash
#
#
#
source $NETOP_ROOT_DIR/global_ops.cfg
#K8SVER="1.34.9-1.1"
NODE_IP=${1}
shift
apt-get update
apt-get install -y --allow-change-held-packages kubelet=${K8SVER} kubeadm=${K8SVER} kubectl=${K8SVER}
apt-mark hold kubelet kubeadm kubectl

# Verify on worker:

/usr/bin/kubelet --version
dpkg -l kubelet kubeadm kubectl
#
if  [ "${NODE_IP}" !+ "" ];then
  sed -i 's/KUBELET_EXTRA_ARGS=--node-ip=.*/KUBELET_EXTRA_ARGS=--node-ip='${NODE_IP}'/' /etc/default/kubelet
fi
tee /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf << 'EOF'
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generate at runtime
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
# Remove the incomplete config
rm /usr/lib/systemd/system/kubelet.service.d/90-kubelet.conf

# Reload systemd
systemctl daemon-reload

# Restart kubelet
echo "Restarting kubelet..."
if ! systemctl restart kubelet; then
    echo "ERROR: Failed to restart kubelet"
    exit 1
fi

# Check status
systemctl status kubelet
