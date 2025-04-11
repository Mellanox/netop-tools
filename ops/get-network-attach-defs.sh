#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NAMESPACE}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} get Network-Attachment-Definitions -o yaml -n ${1}
