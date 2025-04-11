#!/bin/bash
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
# get the node resources
#${K8CL} get no -o json | jq -r '[.items[] | {name:.metadata.name, allocable:.status.allocatable}]'
${K8CL} get no -o json | jq -r '[.items[] | {name:.metadata.name, allocable:.status}]'

