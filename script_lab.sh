#!/bin/bash
#===============================================================================
# Script: script_lab.sh
# Purpose: Configure control plane with network operator and run RDMA tests
#===============================================================================

set -euo pipefail

# Configuration - set these before running
source ${NETOP_ROOT_DIR}/global_ops.cfg
NETOP_TOOLS_REPO="${NETOP_TOOLS_REPO:-https://github.com/nvidia/netop-tools.git}"

# Global variables for cross-function state
WORKER_NODES=""
ELAPSED=0
MAX_WAIT=300

function wait_for_sriov_dp() {
    # Wait for network-operator SRIOV to be ready on worker nodes
    
    # Get worker nodes
    WORKER_NODES=$(kubectl get nodes --no-headers -l node-role.kubernetes.io/worker 2>/dev/null | awk '{print $1}')
    if [[ -z "$WORKER_NODES" ]]; then
        # Try without label filter
        WORKER_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v control-plane | awk '{print $1}')
    fi
    
    echo "Worker nodes: $WORKER_NODES"
    
    # Wait for SriovNetworkNodeState to be ready on each worker
    local max_wait=300
    local interval=10
    local elapsed=0
    
    for node in $WORKER_NODES; do
        echo "Waiting for SriovNetworkNodeState on $node..."
        elapsed=0
        while [[ $elapsed -lt $max_wait ]]; do
            STATE=$(kubectl get sriovnetworknodestates.sriovnetwork.openshift.io "$node" -n nvidia-network-operator -o jsonpath='{.status.syncStatus}' 2>/dev/null || echo "NotFound")
            if [[ "$STATE" == "Succeeded" ]]; then
                echo "  $node: SRIOV ready (syncStatus=Succeeded)"
                break
            fi
            echo "  $node: syncStatus=$STATE, waiting..."
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        if [[ $elapsed -ge $max_wait ]]; then
            echo "WARNING: Timeout waiting for SRIOV on $node"
        fi
    done
}

function check_test_image() {
    # Extract image name from test yaml and check if it exists on worker nodes
    local test_image
    test_image=$(grep -h "image:" test1*.yaml test2*.yaml 2>/dev/null | grep -v "^[[:space:]]*#" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
    echo "Test image: $test_image"
    
    # Check if image exists on first worker node
    local image_exists=false
    local first_worker
    first_worker=$(echo "$WORKER_NODES" | head -1)
    if [[ -n "$first_worker" && -n "$test_image" ]]; then
        echo "Checking if image exists on worker $first_worker..."
        # SSH to worker and check crictl images
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$first_worker" "crictl images 2>/dev/null | grep -q '$(echo "$test_image" | cut -d: -f1)'" 2>/dev/null; then
            image_exists=true
            echo "  Image found on worker - using 3 minute timeout"
        else
            echo "  Image not found on worker - using 10 minute timeout (image must be pulled)"
        fi
    fi
    
    if [[ "$image_exists" == "true" ]]; then
        MAX_WAIT=180   # 3 minutes
    else
        MAX_WAIT=600   # 10 minutes
    fi
    
    ELAPSED=0
    while [[ $ELAPSED -lt $MAX_WAIT ]]; do
        local test1_status test2_status
        test1_status=$(kubectl get pod test1-1 -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        test2_status=$(kubectl get pod test2-1 -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        
        echo "  test1-1: $test1_status, test2-1: $test2_status ($ELAPSED/$MAX_WAIT sec)"
        
        if [[ "$test1_status" == "Running" && "$test2_status" == "Running" ]]; then
            echo "All test pods are Running!"
            return 0
        fi
        
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    return 1
}

# Configure a single control plane
configure_controlplane() {
    # Clone the repository
    if [[ ! -d "$NETOP_ROOT_DIR" ]]; then
        git clone "$NETOP_TOOLS_REPO" "$NETOP_ROOT_DIR"
    else
        echo "Directory $NETOP_ROOT_DIR already exists, skipping clone"
    fi
    
    # Configure global_ops_user.cfg symlink
    cd "$NETOP_ROOT_DIR"
    
    # Create the symlink if it doesn't exist
    if [[ ! -L ./global_ops_user.cfg ]]; then
        ln -s ./config/kvm/global_ops_user.cfg.DGXH100.bcm.hostsriov ./global_ops_user.cfg
    fi
    
    # Source the environment script
    # shellcheck disable=SC1091
    . NETOP_ROOT_DIR.sh
    
    # Run setuc.sh
    ./setuc.sh
    
    # Configure use case
    cd ./uc
    "$NETOP_ROOT_DIR/ops/mk-config.sh"
    cd ..
    
    # Install components
    cd ./install
    
    ./ins-helm.sh
    ./ins-helm-repo.sh
    ./ins-netop-chart.sh
    ./ins-network-operator.sh
    
    cd ..
    
    # Wait for sriov_dp work pod ready
    wait_for_sriov_dp
    
    # Create sample apps
    pushd . > /dev/null
    cd ./uc
    
    "$NETOP_ROOT_DIR/ops/mk-app.sh" test1 1
    "$NETOP_ROOT_DIR/ops/mk-app.sh" test2 1
    
    # Apply the app yamls
    cd apps
    kubectl apply -f test1*.yaml
    kubectl apply -f test2*.yaml
    
    # Wait for test pods to reach Running state
    echo ""
    echo "Waiting for test pods to reach Running state..."
    
    if ! check_test_image; then
        echo "WARNING: Timeout waiting for test pods"
        kubectl get pods
        echo "Skipping RDMA tests due to pods not ready"
        echo ""
        echo "Control plane configuration complete (with warnings)"
        popd > /dev/null
        return 0
    fi
    
    popd > /dev/null
    
    # Run RDMA tests
    echo "Running RDMA tests..."
    cd ./rdmatest
    
    # Start server script in background
    ./gdrsrv.sh roce test1-1 --net net1 > gdrsrv.log 2>&1 &
    SERVER_PID=$!
    echo "  Server PID: $SERVER_PID"
    
    # Brief pause to let server start
    sleep 3
    
    # Start client script in background
    ./gdrclt.sh roce test2-1 test1-1 --net net1 > gdrclt.log 2>&1 &
    CLIENT_PID=$!
    echo "  Client PID: $CLIENT_PID"
    
    # Wait for both scripts to complete
    echo "Waiting for RDMA tests to complete..."
    wait $CLIENT_PID
    CLIENT_EXIT=$?
    echo "  Client completed (exit code: $CLIENT_EXIT)"
    
    wait $SERVER_PID
    SERVER_EXIT=$?
    echo "  Server completed (exit code: $SERVER_EXIT)"
    
    # Output results
    echo ""
    echo "=========================================="
    echo "RDMA Server Log (gdrsrv.log):"
    echo "=========================================="
    cat gdrsrv.log
    
    echo ""
    echo "=========================================="
    echo "RDMA Client Log (gdrclt.log):"
    echo "=========================================="
    cat gdrclt.log
    
    echo ""
    echo "Control plane configuration complete"
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_controlplane "$@"
fi
