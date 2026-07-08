#!/bin/bash
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} config set-context --current --namespace=${1}
