#!/bin/bash
#
# https://docs.tigera.io/calico/3.25/getting-started/kubernetes/helm
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
CALICO_DIR="${NETOP_ROOT_DIR}/release/calico-${CALICO_VERSION}"
# Install the Tigera Calico operator and custom resource definitions using the Helm chart:
${K8CL} delete -f ${CALICO_DIR}/custom-resources.yaml
helm uninstall calico projectcalico/tigera-operator --namespace tigera-operator
#
# Create the tigera-operator namespace.
#
${K8CL} delete namespace tigera-operator

#
# delete existing tigera-operator namespace.
#
${NETOP_ROOT_DIR}/ops/delhelmchart.sh calico tigera-operator
#
# delete the calico repo
#
helm repo remove projectcalico https://docs.tigera.io/calico/charts

