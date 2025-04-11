#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} edit Network-Attachment-Definitions -o yaml -n ${NETOP_NAMESPACE}
