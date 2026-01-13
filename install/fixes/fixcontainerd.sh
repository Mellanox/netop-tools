#!/bin/bash
#
# https://github.com/containerd/containerd/issues/6009
# Container Runtime Configuration - handles both Docker and containerd
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/install/detect_runtime.sh

configure_container_runtime

case "${CONTAINER_RUNTIME}" in
    "containerd")
        echo "Configuring containerd for Kubernetes ${K8SVER}"
        CONTAINERD_CONFIG=/etc/containerd/config.toml
        
        # Generate default config
        containerd config default | sudo tee $CONTAINERD_CONFIG
        
        # Configure systemd cgroup driver
        sed -i 's#SystemdCgroup =.*#SystemdCgroup = true#' $CONTAINERD_CONFIG
        
        # Update pause image for K8s version compatibility
        if [ "${K8SVER}" \> "1.33" ]; then
            # K8s 1.34+ needs newer pause image
            sed -i 's#sandbox_image = "registry.k8s.io/pause:.*"#sandbox_image = "registry.k8s.io/pause:3.12"#' $CONTAINERD_CONFIG
        elif [ "${K8SVER}" \> "1.29" ]; then
            # K8s 1.30-1.33 
            sed -i 's#sandbox_image = "registry.k8s.io/pause:.*"#sandbox_image = "registry.k8s.io/pause:3.10"#' $CONTAINERD_CONFIG
        else
            # K8s 1.29 and earlier
            sed -i 's#sandbox_image = "registry.k8s.io/pause:.*"#sandbox_image = "registry.k8s.io/pause:3.8"#' $CONTAINERD_CONFIG
        fi
        
        # Restart services
        systemctl restart containerd
        systemctl restart kubelet 2>/dev/null || true  # kubelet might not be running yet
        
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
        systemctl restart docker
        systemctl restart kubelet 2>/dev/null || true  # kubelet might not be running yet
        
        echo "Docker configured successfully"
        ;;
        
    "crio")
        echo "CRI-O detected - using default configuration"
        systemctl restart crio
        systemctl restart kubelet 2>/dev/null || true
        ;;
        
    *)
        echo "ERROR: Unsupported container runtime: ${CONTAINER_RUNTIME}"
        exit 1
        ;;
esac

echo "Container runtime ${CONTAINER_RUNTIME} configured for Kubernetes ${K8SVER}"
