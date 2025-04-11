#!/bin/bash
#
# get ippool resource
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
case $# in
1|2)
  ;;
*)
cat << USAGE
usage "$0 {CIDRPOOL NAME} # default to namespace {NETOP_NAMESPACE}
usage "$0 {CIDRPOOL NAME} {NAMESPACE}
USAGE
  exit 1
  ;;
esac
CIDRPOOL=${1}
shift
NS=${1:-${NETOP_NAMESPACE}}
shift
${K8CL} -n ${NS} get cidrpool.nv-ipam.nvidia.com/${CIDRPOOL} -o yaml
