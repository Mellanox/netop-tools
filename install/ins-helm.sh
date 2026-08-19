#!/bin/bash
#
# Install Helm package manager
#
set -euo pipefail

echo "Installing Helm package manager..."

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HELM_INSTALLER="${SCRIPT_DIR}/get_helm.sh"
HELM_INSTALLER_SHA256="cc0e1204ee1dcc79c4b7bb4e9948e74c36a7d8427a1a1d865383c1bdf465cf7f"

if [ -z "${NETOP_ROOT_DIR:-}" ]; then
    echo "ERROR: NETOP_ROOT_DIR is not set"
    exit 1
fi

if [ ! -r "${NETOP_ROOT_DIR}/global_ops.cfg" ]; then
    echo "ERROR: Configuration file not found: ${NETOP_ROOT_DIR}/global_ops.cfg"
    exit 1
fi

source "${NETOP_ROOT_DIR}/global_ops.cfg"

if [ -z "${HELM_VERSION:-}" ]; then
    echo "ERROR: HELM_VERSION is not set in global configuration"
    exit 1
fi

if [ ! -x "${HELM_INSTALLER}" ]; then
    echo "ERROR: Helm installer not found or not executable: ${HELM_INSTALLER}"
    exit 1
fi

echo "Verifying vendored Helm installer..."
if ! echo "${HELM_INSTALLER_SHA256}  ${HELM_INSTALLER}" | sha256sum -c -; then
    echo "ERROR: Helm installer checksum verification failed"
    exit 1
fi

if [ -n "${HELM_VERSION:-}" ] && [ -z "${DESIRED_VERSION:-}" ]; then
    export DESIRED_VERSION="v${HELM_VERSION#v}"
fi

echo "Running Helm installer..."
if ! "${HELM_INSTALLER}"; then
    echo "ERROR: Helm installation failed"
    exit 1
fi

echo "Helm installation completed successfully"
