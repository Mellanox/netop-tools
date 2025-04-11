#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} -n ${1} patch daemonset ${2} -p '{"spec": {"template": {"spec": {"nodeSelector": {"non-existing": "true"}}}}}'
