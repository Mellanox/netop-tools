#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
kubectl patch sriovoperatorconfigs.sriovnetwork.openshift.io -n ${NETOP_NAMESPACE} default --patch '{ "spec": { "featureGates": { "parallelNicConfig": true  }
} }' --type='merge'
