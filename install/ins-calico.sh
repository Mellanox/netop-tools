#!/bin/bash
#
# Install Calico CNI (Container Network Interface)
# Reference: https://docs.tigera.io/calico/3.25/getting-started/kubernetes/helm
# This script installs Calico as the Kubernetes networking solution
#
set -euo pipefail

# Validate environment
if [ -z "${NETOP_ROOT_DIR:-}" ]; then
    echo "ERROR: NETOP_ROOT_DIR is not set"
    exit 1
fi

source "${NETOP_ROOT_DIR}/global_ops.cfg"

echo "Installing Calico ${CALICO_VERSION}..."

# Create release directory
CALICO_DIR="${NETOP_ROOT_DIR}/release/calico-${CALICO_VERSION}"
if [ ! -d "${CALICO_DIR}" ]; then
    echo "Creating directory: ${CALICO_DIR}"
    mkdir -p "${CALICO_DIR}"
fi

cd "${CALICO_DIR}"

# Download Calico manifests
echo "Downloading Calico manifests..."
if [ ! -f ./tigera-operator.yaml ]; then
    echo "Downloading tigera-operator.yaml..."
    if ! curl -fsSL -o ./tigera-operator.yaml "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"; then
        echo "ERROR: Failed to download tigera-operator.yaml"
        exit 1
    fi
fi

if [ ! -f ./custom-resources.yaml ]; then
    echo "Downloading custom-resources.yaml..."
    if ! curl -fsSL -o ./custom-resources.yaml "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml"; then
        echo "ERROR: Failed to download custom-resources.yaml"
        exit 1
    fi
fi
# Clean up any existing installation
echo "Cleaning up existing Calico installation..."
"${NETOP_ROOT_DIR}/uninstall/delhelmchart.sh" calico tigera-operator 2>/dev/null || true

# Handle tigera-operator namespace
echo "Managing tigera-operator namespace..."
if "${K8CL}" get namespace tigera-operator >/dev/null 2>&1; then
    echo "Deleting existing tigera-operator namespace..."
    "${K8CL}" delete namespace tigera-operator
    # Wait for namespace to be fully deleted
    echo "Waiting for namespace deletion to complete..."
    timeout=60
    while [ $timeout -gt 0 ] && "${K8CL}" get namespace tigera-operator >/dev/null 2>&1; do
        sleep 2
        timeout=$((timeout - 2))
    done
    if [ $timeout -le 0 ]; then
        echo "WARNING: Namespace deletion timed out, continuing anyway..."
    fi
fi

echo "Creating tigera-operator namespace..."
if ! "${K8CL}" create namespace tigera-operator; then
    echo "ERROR: Failed to create tigera-operator namespace"
    exit 1
fi

# Add Calico Helm repository
echo "Adding Calico Helm repository..."
if ! helm repo add projectcalico https://docs.tigera.io/calico/charts; then
    echo "ERROR: Failed to add Calico Helm repository"
    exit 1
fi

echo "Updating Helm repositories..."
if ! helm repo update; then
    echo "ERROR: Failed to update Helm repositories"
    exit 1
fi

# Install Calico operator
echo "Installing Calico operator ${CALICO_VERSION}..."
if ! helm install calico projectcalico/tigera-operator --version "${CALICO_VERSION}" --namespace tigera-operator; then
    echo "ERROR: Failed to install Calico operator"
    exit 1
fi

# Apply custom resources
echo "Applying Calico custom resources..."
if ! "${K8CL}" apply -f ./custom-resources.yaml; then
    echo "ERROR: Failed to apply Calico custom resources"
    exit 1
fi

# Configure Calico BIRD (BGP)
echo "Configuring Calico BIRD..."
"${NETOP_ROOT_DIR}/install/fixes/fix_calico_bird.sh"

echo "Calico installation completed successfully"
#helm install calico projectcalico/tigera-operator --version ${CALICO_VERSION} -f values.yaml --namespace tigera-operator
### #${K8CL} create -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml
### #${K8CL} create -f https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/custom-resources.yaml
### # Create the tigera-operator namespace.
### # get the error message that this already exists
### ${K8CL} create namespace tigera-operator
### 
### helm repo add projectcalico https://docs.tigera.io/calico/charts
### # Install the Tigera Calico operator and custom resource definitions using the Helm chart:
### 
### #helm install calico projectcalico/tigera-operator --version ${CALICO_VERSION} --namespace tigera-operator
### helm install calico projectcalico/tigera-operator --namespace tigera-operator
### 
### ${K8CL} apply -f ./calico/calico-custom-resources.yaml
### #helm upgrade tigera-operator -f calico/calico-custom-resources.yaml tigera-operator
### # or if you created a values.yaml above:
### 
### #helm install calico projectcalico/tigera-operator --version ${CALICO_VERSION} -f values.yaml --namespace tigera-operator
