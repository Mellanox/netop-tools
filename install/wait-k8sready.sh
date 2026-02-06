#!/bin/bash
#
# Wait for Kubernetes core components to be ready
#
set -euo pipefail

# Validate environment
if [ -z "${NETOP_ROOT_DIR:-}" ]; then
    echo "ERROR: NETOP_ROOT_DIR is not set"
    exit 1
fi

if [ -z "${K8CL:-}" ]; then
    echo "ERROR: K8CL (kubectl command) is not set"
    exit 1
fi

echo "Waiting for Kubernetes core components to be ready..."

source "${NETOP_ROOT_DIR}/install/readytest.sh"

# Define required pods: count,namespace,pod-name-pattern
PODLIST=( 1,kube-system,etcd 1,kube-system,kube-apiserver 1,kube-system,kube-controller-manager 1,kube-system,kube-scheduler )

# Test kubectl connectivity first
if ! "${K8CL}" cluster-info >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "Check that kubectl is configured and cluster is accessible"
    exit 1
fi

# Wait for pods to be ready
nsReady
