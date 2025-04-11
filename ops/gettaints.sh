#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} get nodes -o=custom-columns=NodeName:.metadata.name,TaintKey:.spec.taints[*].key,TaintValue:.spec.taints[*].value,TaintEffect:.spec.taints[*].effect
#  NodeName                                        TaintKey
