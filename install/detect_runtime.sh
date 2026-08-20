#!/bin/bash
#
# Container Runtime Detection for Kubernetes
# Detects and configures the appropriate container runtime
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"

# Returns 0 (true) if version $1 is greater than $2 using sort -V
function version_gt() { test "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" && test "$1" != "$2"; }

function require_cri_dockerd_integrity_config() {
    local name="${1}"
    local value="${2}"

    if [ -z "${value}" ]; then
        echo "ERROR: ${name} is required for cri-dockerd ${CRI_DOCKERD_VERSION}.${CRI_DOCKERD_ARCH}"
        echo "ERROR: Set ${name} to a pinned upstream value before installing this cri-dockerd version"
        exit 1
    fi
}

function set_cri_dockerd_integrity_defaults() {
    case "${CRI_DOCKERD_VERSION}.${CRI_DOCKERD_ARCH}" in
        0.3.15.amd64)
            CRI_DOCKERD_COMMIT_SHA="${CRI_DOCKERD_COMMIT_SHA:-c1c566e0cc84abe6972f0bf857ecd8fe306258d9}"
            CRI_DOCKERD_TARBALL_SHA256="${CRI_DOCKERD_TARBALL_SHA256:-4779b7c3663f002871e79ecf6aa8eb48d0bb74df035baecf56b816deb21d12c4}"
            CRI_DOCKERD_SERVICE_SHA256="${CRI_DOCKERD_SERVICE_SHA256:-1600eaa78186ecd068be61bb589ed23eca8f07d4dc6032e0ab84d7e9c9bb22d0}"
            CRI_DOCKERD_SOCKET_SHA256="${CRI_DOCKERD_SOCKET_SHA256:-01d2ea8973c71de9369f188773854e9f23d9359c4549c119508976649918ca86}"
            ;;
    esac

    require_cri_dockerd_integrity_config CRI_DOCKERD_COMMIT_SHA "${CRI_DOCKERD_COMMIT_SHA:-}"
    require_cri_dockerd_integrity_config CRI_DOCKERD_TARBALL_SHA256 "${CRI_DOCKERD_TARBALL_SHA256:-}"
    require_cri_dockerd_integrity_config CRI_DOCKERD_SERVICE_SHA256 "${CRI_DOCKERD_SERVICE_SHA256:-}"
    require_cri_dockerd_integrity_config CRI_DOCKERD_SOCKET_SHA256 "${CRI_DOCKERD_SOCKET_SHA256:-}"
}

function verify_sha256() {
    local expected_sha256="${1}"
    local file_path="${2}"

    echo "${expected_sha256}  ${file_path}" | sha256sum -c -
}

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
                if version_gt "${K8SVER}" "1.23"; then
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
                if version_gt "${K8SVER}" "1.23"; then
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
            if version_gt "${K8SVER}" "1.23"; then
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
        CRI_DOCKERD_ARCH="${CRI_DOCKERD_ARCH:-amd64}"
        set_cri_dockerd_integrity_defaults
        
        # Check if already installed
        if command -v cri-dockerd >/dev/null 2>&1; then
            echo "cri-dockerd already installed"
            return 0
        fi
        
        # Download and install cri-dockerd
        CRI_DOCKERD_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/netop-cri-dockerd.XXXXXX")
        CRI_DOCKERD_TARBALL="cri-dockerd-${CRI_DOCKERD_VERSION}.${CRI_DOCKERD_ARCH}.tgz"
        CRI_DOCKERD_TARBALL_PATH="${CRI_DOCKERD_TMP_DIR}/${CRI_DOCKERD_TARBALL}"
        CRI_DOCKERD_SERVICE_PATH="${CRI_DOCKERD_TMP_DIR}/cri-docker.service"
        CRI_DOCKERD_SOCKET_PATH="${CRI_DOCKERD_TMP_DIR}/cri-docker.socket"

        if ! curl -fL -o "${CRI_DOCKERD_TARBALL_PATH}" "https://github.com/Mirantis/cri-dockerd/releases/download/v${CRI_DOCKERD_VERSION}/${CRI_DOCKERD_TARBALL}"; then
            echo "ERROR: Failed to download cri-dockerd"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        if ! verify_sha256 "${CRI_DOCKERD_TARBALL_SHA256}" "${CRI_DOCKERD_TARBALL_PATH}"; then
            echo "ERROR: cri-dockerd archive checksum verification failed"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi

        if ! curl -fL -o "${CRI_DOCKERD_SERVICE_PATH}" "https://raw.githubusercontent.com/Mirantis/cri-dockerd/${CRI_DOCKERD_COMMIT_SHA}/packaging/systemd/cri-docker.service"; then
            echo "ERROR: Failed to download cri-docker.service"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        if ! verify_sha256 "${CRI_DOCKERD_SERVICE_SHA256}" "${CRI_DOCKERD_SERVICE_PATH}"; then
            echo "ERROR: cri-docker.service checksum verification failed"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi

        if ! curl -fL -o "${CRI_DOCKERD_SOCKET_PATH}" "https://raw.githubusercontent.com/Mirantis/cri-dockerd/${CRI_DOCKERD_COMMIT_SHA}/packaging/systemd/cri-docker.socket"; then
            echo "ERROR: Failed to download cri-docker.socket"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        if ! verify_sha256 "${CRI_DOCKERD_SOCKET_SHA256}" "${CRI_DOCKERD_SOCKET_PATH}"; then
            echo "ERROR: cri-docker.socket checksum verification failed"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        
        if ! tar -xf "${CRI_DOCKERD_TARBALL_PATH}" -C "${CRI_DOCKERD_TMP_DIR}"; then
            echo "ERROR: Failed to extract cri-dockerd archive"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        if [ ! -x "${CRI_DOCKERD_TMP_DIR}/cri-dockerd/cri-dockerd" ]; then
            echo "ERROR: cri-dockerd binary missing from verified archive"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        if ! sudo install -m 0755 "${CRI_DOCKERD_TMP_DIR}/cri-dockerd/cri-dockerd" /usr/local/bin/cri-dockerd; then
            echo "ERROR: Failed to install cri-dockerd binary"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        
        # Install systemd service files
        if ! sudo install -m 0644 "${CRI_DOCKERD_SERVICE_PATH}" /etc/systemd/system/cri-docker.service; then
            echo "ERROR: Failed to install cri-docker.service"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        if ! sudo install -m 0644 "${CRI_DOCKERD_SOCKET_PATH}" /etc/systemd/system/cri-docker.socket; then
            echo "ERROR: Failed to install cri-docker.socket"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        if ! sudo sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service; then
            echo "ERROR: Failed to update cri-docker.service binary path"
            rm -rf "${CRI_DOCKERD_TMP_DIR}"
            exit 1
        fi
        
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
        rm -rf "${CRI_DOCKERD_TMP_DIR}"
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
