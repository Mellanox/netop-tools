#!/bin/bash
#
# get ippool resource
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"
case $# in
0|1)
  ;;
*)
cat << USAGE
usage "$0 # default to namespace {NETOP_NAMESPACE}
usage "$0 {NAMESPACE}
USAGE
  exit 1
  ;;
esac
shift
NS=${1:-${NETOP_NAMESPACE}}
shift
#kubectl -n ${NS} get ippool.nv-ipam.nvidia.com -o yaml
kubectl -n ${NS} get ippool.nv-ipam.nvidia.com
