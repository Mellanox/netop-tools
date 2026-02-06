#!/bin/bash
#
# Install Helm package manager
#
set -euo pipefail

echo "Installing Helm package manager..."

# Download Helm installation script
echo "Downloading Helm installer..."
if ! curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3; then
    echo "ERROR: Failed to download Helm installer"
    exit 1
fi

# Make executable
chmod 700 get_helm.sh

# Run installer
echo "Running Helm installer..."
if ! ./get_helm.sh; then
    echo "ERROR: Helm installation failed"
    exit 1
fi

# Cleanup
rm -f get_helm.sh

echo "Helm installation completed successfully"
