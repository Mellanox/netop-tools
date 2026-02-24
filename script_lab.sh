
function wait_for_sriov_dp()
{
# Wait for network-operator SRIOV to be ready on worker nodes

# Get worker nodes
WORKER_NODES=$(kubectl get nodes --no-headers -l node-role.kubernetes.io/worker 2>/dev/null | awk '{print $1}')
if [[ -z "$WORKER_NODES" ]]; then
    # Try without label filter
    WORKER_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -v control-plane | awk '{print $1}')
fi

echo "Worker nodes: $WORKER_NODES"

# Wait for SriovNetworkNodeState to be ready on each worker
MAX_WAIT=300
INTERVAL=10
ELAPSED=0

for node in $WORKER_NODES; do
    echo "Waiting for SriovNetworkNodeState on $node..."
    while [[ $ELAPSED -lt $MAX_WAIT ]]; do
        STATE=$(kubectl get sriovnetworknodestates.sriovnetwork.openshift.io "$node" -n nvidia-network-operator -o jsonpath='{.status.syncStatus}' 2>/dev/null || echo "NotFound")
        if [[ "$STATE" == "Succeeded" ]]; then
            echo "  $node: SRIOV ready (syncStatus=Succeeded)"
            break
        fi
        echo "  $node: syncStatus=$STATE, waiting..."
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    if [[ $ELAPSED -ge $MAX_WAIT ]]; then
        echo "WARNING: Timeout waiting for SRIOV on $node"
    fi
done
}
function check_test_image()
{
# Extract image name from test yaml and check if it exists on worker nodes
TEST_IMAGE=$(grep -h "image:" test1*.yaml test2*.yaml 2>/dev/null | grep -v "^[[:space:]]*#" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
echo "Test image: $TEST_IMAGE"

# Check if image exists on first worker node
IMAGE_EXISTS=false
FIRST_WORKER=$(echo "$WORKER_NODES" | head -1)
if [[ -n "$FIRST_WORKER" && -n "$TEST_IMAGE" ]]; then
    echo "Checking if image exists on worker $FIRST_WORKER..."
    # SSH to worker and check crictl images
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$FIRST_WORKER" "crictl images 2>/dev/null | grep -q '$(echo $TEST_IMAGE | cut -d: -f1)'" 2>/dev/null; then
        IMAGE_EXISTS=true
        echo "  Image found on worker - using 3 minute timeout"
    else
        echo "  Image not found on worker - using 10 minute timeout (image must be pulled)"
    fi
fi

if [[ "$IMAGE_EXISTS" == "true" ]]; then
    MAX_WAIT=180   # 3 minutes
else
    MAX_WAIT=600   # 10 minutes
fi

ELAPSED=0
while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    TEST1_STATUS=$(kubectl get pod test1-1 -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    TEST2_STATUS=$(kubectl get pod test2-1 -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    echo "  test1-1: $TEST1_STATUS, test2-1: $TEST2_STATUS ($ELAPSED/$MAX_WAIT sec)"
    
    if [[ "$TEST1_STATUS" == "Running" && "$TEST2_STATUS" == "Running" ]]; then
        echo "All test pods are Running!"
        break
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
}
# Configure a single control plane
configure_controlplane() {
# Clone the repository
git clone "$NETOP_TOOLS_REPO"

# Verify
# Configure global_ops_user.cfg symlink
cd "$NETOP_TOOLS_DIR"

# Create the symlink
ln -s ./config/kvm/global_ops_user.cfg.DGXH100.bcm.hostsriov ./global_ops_user.cfg

# Source the environment script
. NETOP_ROOT_DIR.sh

# Run setuc.sh
./setuc.sh

# Configure use case
cd ./uc
$NETOP_ROOT_DIR/ops/mk-config.sh
cd ..

# Install components
cd ./install

./ins-helm.sh

./ins-helm-repo.sh

./ins-netop-chart.sh

./ins-network-operator.sh

cd ..
# wait for sriov_dp work pod ready
wait_for_sriov_dp

# Create sample apps
pushd .
cd ./uc

$NETOP_ROOT_DIR/ops/mk-app.sh test1 1

$NETOP_ROOT_DIR/ops/mk-app.sh test2 1

# Apply the app yamls
cd apps
kubectl apply -f test1*.yaml
kubectl apply -f test2*.yaml

# Wait for test pods to reach Running state
echo ""
echo "Waiting for test pods to reach Running state..."

check_test_image()

if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    echo "WARNING: Timeout waiting for test pods"
    kubectl get pods
    echo "Skipping RDMA tests due to pods not ready"
    echo ""
    echo "Control plane configuration complete (with warnings)"
    exit 0
fi

popd
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

