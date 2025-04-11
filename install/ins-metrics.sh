#!/bin/bash
#
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
