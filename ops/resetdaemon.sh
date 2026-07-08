#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} rollout restart daemonset/${1} -n ${NETOP_NAMESPACE}
