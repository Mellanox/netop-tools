#!/bin/bash
#
# Container Runtime Detection for Kubernetes
# Detects and configures the appropriate container runtime
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

function detect_container_runtime() {
    echo "Detecting container runtime..."
    
    # Check what's actually running and configured
    if systemctl is-active docker >/dev/null 2>&1; then
        # Docker is running - check if it's the K8s runtime
        if [ -f /var/lib/kubelet/config.yaml ]; then
            # Kubelet config exists, check container runtime
            if grep -q "docker" /var/lib/kubelet/config.yaml 2>/dev/null || \
               grep -q "cri-dockerd" /var/lib/kubelet/config.yaml 2>/dev/null; then
                CONTAINER_RUNTIME="docker"
                if [ "${K8SVER}" \> "1.23" ]; then
                    # K8s 1.24+ needs cri-dockerd
                    CRI_SOCKET="unix:///var/run/cri-dockerd.sock"
                    NEEDS_CRI_DOCKERD=true
                else
                    # K8s 1.23 and earlier with dockershim
                    CRI_SOCKET="unix:///var/run/dockershim.sock"
                    NEEDS_CRI_DOCKERD=false
                fi
            else
                CONTAINER_RUNTIME="containerd"
                CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
                NEEDS_CRI_DOCKERD=false
            fi
        else
            # No kubelet config yet - check what services are enabled
            if systemctl is-enabled containerd >/dev/null 2>&1; then
                CONTAINER_RUNTIME="containerd"
                CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
                NEEDS_CRI_DOCKERD=false
            else
                CONTAINER_RUNTIME="docker"
                if [ "${K8SVER}" \> "1.23" ]; then
                    CRI_SOCKET="unix:///var/run/cri-dockerd.sock"
                    NEEDS_CRI_DOCKERD=true
                else
                    CRI_SOCKET="unix:///var/run/dockershim.sock"
                    NEEDS_CRI_DOCKERD=false
                fi
            fi
        fi
    elif systemctl is-active containerd >/dev/null 2>&1; then
        CONTAINER_RUNTIME="containerd"
        CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
        NEEDS_CRI_DOCKERD=false
    elif systemctl is-active crio >/dev/null 2>&1; then
        CONTAINER_RUNTIME="crio"
        CRI_SOCKET="unix:///var/run/crio/crio.sock"
        NEEDS_CRI_DOCKERD=false
    else
        # Nothing running yet - check what's installed
        if command -v containerd >/dev/null 2>&1; then
            CONTAINER_RUNTIME="containerd"
            CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
            NEEDS_CRI_DOCKERD=false
        elif command -v docker >/dev/null 2>&1; then
            CONTAINER_RUNTIME="docker"
            if [ "${K8SVER}" \> "1.23" ]; then
                CRI_SOCKET="unix:///var/run/cri-dockerd.sock"
                NEEDS_CRI_DOCKERD=true
            else
                CRI_SOCKET="unix:///var/run/dockershim.sock"
                NEEDS_CRI_DOCKERD=false
            fi
        else
            echo "ERROR: No supported container runtime found (docker, containerd, or crio)"
            exit 1
        fi
    fi
    
    export CONTAINER_RUNTIME CRI_SOCKET NEEDS_CRI_DOCKERD
    echo "Detected container runtime: ${CONTAINER_RUNTIME}"
    echo "CRI socket: ${CRI_SOCKET}"
    if [ "${NEEDS_CRI_DOCKERD}" = "true" ]; then
        echo "Will install cri-dockerd for K8s ${K8SVER} compatibility"
    fi
}

function install_cri_dockerd() {
    if [ "${NEEDS_CRI_DOCKERD}" = "true" ]; then
        echo "Installing cri-dockerd for Docker compatibility with K8s ${K8SVER}"
        
        # Use version from global configuration, fallback to default
        CRI_DOCKERD_VERSION="${CRI_DOCKERD_VERSION:-0.3.15}"
        
        # Check if already installed
        if command -v cri-dockerd >/dev/null 2>&1; then
            echo "cri-dockerd already installed"
            return 0
        fi
        
        # Download and install cri-dockerd
        cd /tmp
        wget -q https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKERD_VERSION}/cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
        if [ $? -ne 0 ]; then
            echo "ERROR: Failed to download cri-dockerd"
            exit 1
        fi
        
        tar -xf cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
        sudo mv cri-dockerd/cri-dockerd /usr/local/bin/
        sudo chmod +x /usr/local/bin/cri-dockerd
        
        # Install systemd service files
        sudo curl -sL https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.service -o /etc/systemd/system/cri-docker.service
        sudo curl -sL https://raw.githubusercontent.com/Mirantis/cri-dockerd/master/packaging/systemd/cri-docker.socket -o /etc/systemd/system/cri-docker.socket
        
        # Enable and start services
        sudo systemctl daemon-reload
        sudo systemctl enable cri-docker.service
        sudo systemctl enable cri-docker.socket
        sudo systemctl start cri-docker.service
        sudo systemctl start cri-docker.socket
        
        # Verify installation
        if ! systemctl is-active cri-docker.service >/dev/null 2>&1; then
            echo "ERROR: cri-dockerd service failed to start"
            systemctl status cri-docker.service
            exit 1
        fi
        
        echo "cri-dockerd installed and running successfully"
        rm -f /tmp/cri-dockerd-${CRI_DOCKERD_VERSION}.amd64.tgz
        rm -rf /tmp/cri-dockerd
    fi
}

function configure_container_runtime() {
    detect_container_runtime
    install_cri_dockerd
    
    echo "Configuring ${CONTAINER_RUNTIME} for Kubernetes ${K8SVER}"
    
    case "${CONTAINER_RUNTIME}" in
        "docker")
            systemctl enable docker
            systemctl restart docker
            ;;
        "containerd")
            systemctl enable containerd
            systemctl restart containerd
            ;;
        "crio")
            systemctl enable crio
            systemctl restart crio
            ;;
    esac
}
