#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} get nodes -o=custom-columns='NAME:metadata.name,ANNOTATION:metadata.annotations.ipam\.nvidia\.com/ip-blocks'
${K8CL} get nodes -o=custom-columns='NAME:metadata.name,ANNOTATION:metadata.annotations.'
