#!/bin/bash
#
# https://github.com/containerd/containerd/issues/6009
# Container Runtime Configuration - handles both Docker and containerd
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/install/detect_runtime.sh

# Helper function for version comparison
version_greater_equal() {
    # Compare versions using sort -V (version sort)
    # Returns 0 if $1 >= $2, 1 otherwise
    [ "$(printf '%s\n%s' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

configure_container_runtime

case "${CONTAINER_RUNTIME}" in
    "containerd")
        echo "Configuring containerd for Kubernetes ${K8SVER}"
        CONTAINERD_CONFIG=/etc/containerd/config.toml
        
        # Generate default config
        containerd config default | sudo tee "$CONTAINERD_CONFIG"
        
        # Configure systemd cgroup driver
        sed -i 's#SystemdCgroup =.*#SystemdCgroup = true#' "$CONTAINERD_CONFIG"
        
        # Update pause image for K8s version compatibility
        if version_greater_equal "${K8SVER}" "1.34"; then
            # K8s 1.34+ needs newer pause image
            echo "Using pause:3.12 for Kubernetes ${K8SVER}"
            sed -i 's#sandbox_image = "registry.k8s.io/pause:.*"#sandbox_image = "registry.k8s.io/pause:3.12"#' "$CONTAINERD_CONFIG"
        elif version_greater_equal "${K8SVER}" "1.30"; then
            # K8s 1.30-1.33 
            echo "Using pause:3.10 for Kubernetes ${K8SVER}"
            sed -i 's#sandbox_image = "registry.k8s.io/pause:.*"#sandbox_image = "registry.k8s.io/pause:3.10"#' "$CONTAINERD_CONFIG"
        else
            # K8s 1.29 and earlier
            echo "Using pause:3.8 for Kubernetes ${K8SVER}"
            sed -i 's#sandbox_image = "registry.k8s.io/pause:.*"#sandbox_image = "registry.k8s.io/pause:3.8"#' "$CONTAINERD_CONFIG"
        fi
        
        # Restart services
        echo "Restarting containerd..."
        if ! systemctl restart containerd; then
            echo "ERROR: Failed to restart containerd"
            exit 1
        fi
        echo "Restarting kubelet (if running)..."
        systemctl restart kubelet 2>/dev/null || echo "kubelet not running yet, will start after kubeadm init"
        
        echo "containerd configured successfully"
        ;;
        
    "docker")
        echo "Configuring Docker for Kubernetes ${K8SVER}"
        
        # Configure Docker daemon for Kubernetes
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
        
        # Restart Docker
        echo "Restarting Docker..."
        if ! systemctl restart docker; then
            echo "ERROR: Failed to restart Docker"
            exit 1
        fi
        echo "Restarting kubelet (if running)..."
        systemctl restart kubelet 2>/dev/null || echo "kubelet not running yet, will start after kubeadm init"
        
        echo "Docker configured successfully"
        ;;
        
    "crio")
        echo "CRI-O detected - using default configuration"
        echo "Restarting CRI-O..."
        if ! systemctl restart crio; then
            echo "ERROR: Failed to restart CRI-O"
            exit 1
        fi
        echo "Restarting kubelet (if running)..."
        systemctl restart kubelet 2>/dev/null || echo "kubelet not running yet, will start after kubeadm init"
        ;;
        
    *)
        echo "ERROR: Unsupported container runtime: ${CONTAINER_RUNTIME}"
        exit 1
        ;;
esac

echo "Container runtime ${CONTAINER_RUNTIME} configured for Kubernetes ${K8SVER}"
