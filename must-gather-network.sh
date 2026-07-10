#!/usr/bin/env bash
# author: Vinod Eswaraprasad
set -o nounset
set -x

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export NETOP_ROOT_DIR=${NETOP_ROOT_DIR:-"${SCRIPT_DIR}"}
source "${NETOP_ROOT_DIR}/global_ops.cfg"

K="${K8CL}"
if ! $K version > /dev/null; then
    echo "FATAL: configured K8CL command '${K8CL}' is not working properly. Exiting ..."
    exit 1
fi

if [[ "$0" == "/usr/bin/gather" ]]; then
    echo "Running as must-gather plugin image"
    export ARTIFACT_DIR=/must-gather
else
    if [ -z "${ARTIFACT_DIR:-}" ]; then
        export ARTIFACT_DIR="/tmp/nvidia-network-operator_$(date +%Y%m%d_%H%M)"
    fi
    echo "Using ARTIFACT_DIR=$ARTIFACT_DIR"
fi

mkdir -p "$ARTIFACT_DIR"

echo

exec 1> >(tee "$ARTIFACT_DIR/must-gather.log")
exec 2> "$ARTIFACT_DIR/must-gather.stderr.log"

if [[ "$0" == "/usr/bin/gather" ]]; then
    echo "Network Operator" > $ARTIFACT_DIR/version
    echo "${VERSION:-N/A}" >> $ARTIFACT_DIR/version
fi

ocp_cluster=$($K get clusterversion/version --ignore-not-found -oname || true)

if [[ "$ocp_cluster" ]]; then
    echo "Running in OpenShift."
    echo "Get the cluster version"
    $K get clusterversion/version -oyaml > $ARTIFACT_DIR/openshift_version.yaml
fi

echo "Get the operator namespaces"
OPERATOR_NAMESPACE="${NETOP_NAMESPACE}"

if [ -z "${OPERATOR_NAMESPACE}" ]; then
    echo "FATAL: NETOP_NAMESPACE is not set ..."
    exit 1
fi

OPERATOR_POD_NAME=$($K get pods -l app.kubernetes.io/name=network-operator -n "$OPERATOR_NAMESPACE" -ojsonpath='{.items[0].metadata.name}' --ignore-not-found)
if [ -z "${OPERATOR_POD_NAME}" ]; then
    echo "FATAL: could not find the Network Operator Pod in namespace ${OPERATOR_NAMESPACE} ..."
    exit 1
fi
OPERATOR_POD_NAME="pod/${OPERATOR_POD_NAME}"

echo "Using '$OPERATOR_NAMESPACE' as operator namespace"
echo ""

function get_resource()
{
    local resource=$1
    local output=$2

    $K get "$resource" -A -oyaml > "$ARTIFACT_DIR/${output}.yaml" 2>/dev/null ||
        $K get "$resource" -oyaml > "$ARTIFACT_DIR/${output}.yaml" 2>/dev/null ||
        true
}

echo "#"
echo "# Operator Pod"
echo "#"
echo

echo "Get the Network Operator Pod (status)"
$K get $OPERATOR_POD_NAME \
    -owide \
    -n $OPERATOR_NAMESPACE \
    > $ARTIFACT_DIR/network_operator_pod.status

echo "Get the Network Operator Pod (yaml)"
$K get $OPERATOR_POD_NAME \
    -oyaml \
    -n $OPERATOR_NAMESPACE \
    > $ARTIFACT_DIR/network_operator_pod.yaml

echo "Get the Network Operator Pod logs"
$K logs $OPERATOR_POD_NAME \
    -n $OPERATOR_NAMESPACE \
    > "$ARTIFACT_DIR/network_operator_pod.log"

$K logs $OPERATOR_POD_NAME \
    -n $OPERATOR_NAMESPACE \
    --previous \
    > "$ARTIFACT_DIR/network_operator_pod.previous.log"

echo "#"
echo "# Operand Pods"
echo "#"
echo ""

echo "Get the Pods in $OPERATOR_NAMESPACE (status)"
$K get pods -owide \
    -n $OPERATOR_NAMESPACE \
    > $ARTIFACT_DIR/network_operand_pods.status

echo "Get the Pods in $OPERATOR_NAMESPACE (yaml)"
$K get pods -oyaml \
    -n $OPERATOR_NAMESPACE \
    > $ARTIFACT_DIR/network_operand_pods.yaml

echo "Get the Network Operator Pods Images"
$K get pods -n $OPERATOR_NAMESPACE \
    -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{range .spec.containers[*]}{.image}{" "}{end}{end}' \
    > $ARTIFACT_DIR/network_operand_pod_images.txt

echo "Get the description and logs of the Network Operator Pods"

for pod in $($K get pods -n $OPERATOR_NAMESPACE -oname);
do
    pod_name=$(echo "$pod" | cut -d/ -f2)

    if [ $pod == $OPERATOR_POD_NAME ]; then
        echo "Skipping operator pod $pod_name ..."
        continue
    fi

    $K logs $pod \
        -n $OPERATOR_NAMESPACE \
        --all-containers --prefix \
        > $ARTIFACT_DIR/network_operand_pod_$pod_name.log

    $K logs $pod \
        -n $OPERATOR_NAMESPACE \
        --all-containers --prefix \
        --previous \
        > $ARTIFACT_DIR/network_operand_pod_$pod_name.previous.log

    $K describe $pod \
        -n $OPERATOR_NAMESPACE \
        > $ARTIFACT_DIR/network_operand_pod_$pod_name.descr

done

echo "#"
echo "# Operand DaemonSets"
echo "#"
echo ""

echo "Get the DaemonSets in $OPERATOR_NAMESPACE (status)"

$K get ds \
    -n $OPERATOR_NAMESPACE \
    > $ARTIFACT_DIR/network_operand_ds.status

echo "Get the DaemonSets in $OPERATOR_NAMESPACE (yaml)"

$K get ds -oyaml \
    -n $OPERATOR_NAMESPACE \
    > $ARTIFACT_DIR/network_operand_ds.yaml

echo "Get the description of the Network Operator DaemonSets"

for ds in $($K get ds -n $OPERATOR_NAMESPACE -oname);
do
    $K describe $ds \
        -n $OPERATOR_NAMESPACE \
        > $ARTIFACT_DIR/network_operand_ds_$(echo "$ds" | cut -d/ -f2).descr
done

echo "#"
echo "# SR-IOV Diagnostics"
echo "#"
echo ""

echo "Get recent events in $OPERATOR_NAMESPACE"
$K get events \
    -n $OPERATOR_NAMESPACE \
    --sort-by=.lastTimestamp \
    > "$ARTIFACT_DIR/network_operator_events.txt"

echo "Get recent cluster events"
$K get events \
    -A \
    --sort-by=.lastTimestamp \
    > "$ARTIFACT_DIR/cluster_events.txt"

echo "Get SR-IOV and Network Operator custom resources"
get_resource nicclusterpolicies.mellanox.com custom_resource_nicclusterpolicies
get_resource nicnodepolicies.mellanox.com custom_resource_nicnodepolicies
get_resource sriovoperatorconfigs.sriovnetwork.openshift.io custom_resource_sriovoperatorconfigs
get_resource sriovnetworknodepolicies.sriovnetwork.openshift.io custom_resource_sriovnetworknodepolicies
get_resource sriovnetworknodestates.sriovnetwork.openshift.io custom_resource_sriovnetworknodestates
get_resource sriovnetworkpoolconfigs.sriovnetwork.openshift.io custom_resource_sriovnetworkpoolconfigs
get_resource sriovnetworks.sriovnetwork.openshift.io custom_resource_sriovnetworks
get_resource network-attachment-definitions.k8s.cni.cncf.io custom_resource_networkattachmentdefinitions
get_resource ippools.nv-ipam.nvidia.com custom_resource_ippools
get_resource cidrpools.nv-ipam.nvidia.com custom_resource_cidrpools

echo "#"
echo "# All done!"
if [[ "$0" != "/usr/bin/gather" ]]; then
    echo "# Logs saved into ${ARTIFACT_DIR}."
fi
echo "#"
