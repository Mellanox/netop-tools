#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
# produces the same output
#${K8CL} get nicclusterpolicies.mellanox.com nic-cluster-policy -o yaml
${K8CL} get NicClusterPolicy nic-cluster-policy -o yaml
