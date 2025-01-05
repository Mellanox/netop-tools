#!/bin/bash
#
# get ippool resource
#
case $# in
1|2)
  ;;
*)
cat << USAGE
usage "$0 {IPPOOL NAME} # default to namespace nvidia-network-operator
usage "$0 {IPPOOL NAME} {NAMESPACE}
USAGE
  exit 1
  ;;
esac
IPPOOL=${1}
shift
NS=${1:-"nvidia-network-operator"}
shift
kubectl -n ${NS} get ippool.nv-ipam.nvidia.com/${IPPOOL} -o yaml
