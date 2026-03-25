#!/bin/bash
#
# Set up use case configuration
# Creates a symlink to the selected use case directory
#
set -euo pipefail

# Validate environment
if [ -z "${NETOP_ROOT_DIR:-}" ]; then
    echo "ERROR: NETOP_ROOT_DIR variable is not set"
    exit 1
fi

if [ ! -d "${NETOP_ROOT_DIR}" ]; then
    echo "ERROR: NETOP_ROOT_DIR directory does not exist: ${NETOP_ROOT_DIR}"
    exit 1
fi

if [ ! -f "${NETOP_ROOT_DIR}/global_ops.cfg" ]; then
    echo "ERROR: Configuration file not found: ${NETOP_ROOT_DIR}/global_ops.cfg"
    exit 1
fi

source "${NETOP_ROOT_DIR}/global_ops.cfg"

# Allow override from command line parameter
if [ $# -gt 0 ]; then
    REQUESTED_USECASE="${1}"
    echo "Using requested use case: ${REQUESTED_USECASE}"
    USECASE="${REQUESTED_USECASE}"
fi

# Validate use case exists
USECASE_DIR="${NETOP_ROOT_DIR}/usecase/${USECASE}"
if [ ! -d "${USECASE_DIR}" ]; then
    echo "ERROR: Use case directory does not exist: ${USECASE_DIR}"
    echo "Available use cases:"
    if [ -d "${NETOP_ROOT_DIR}/usecase" ]; then
        ls -1 "${NETOP_ROOT_DIR}/usecase/" | grep -v "^\." | sed 's/^/  - /'
    fi
    exit 1
fi

# Validate use case has required configuration
if [ ! -f "${USECASE_DIR}/netop.cfg" ]; then
    echo "ERROR: Use case configuration missing: ${USECASE_DIR}/netop.cfg"
    exit 1
fi

# Create/update symlink
UC_LINK="${NETOP_ROOT_DIR}/uc"
echo "Setting up use case: ${USECASE}"
rm -f "${UC_LINK}"
if ! ln -s "${USECASE_DIR}" "${UC_LINK}"; then
    echo "ERROR: Failed to create use case symlink"
    exit 1
fi

echo "Successfully configured use case: ${USECASE}"
echo "Use case directory: ${USECASE_DIR}"
