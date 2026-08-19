#!/bin/bash
#
# drain a node, ignore daemonsets
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"
${K8CL} drain ${1}  --ignore-daemonsets
