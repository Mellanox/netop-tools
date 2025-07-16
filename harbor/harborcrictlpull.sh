#!/bin/bash
#
# need to do docker login ${REGISTRY}
#
function usage()
{
  echo "usage:$0 image # use harbor.cfg defaults"
  echo "usage:$0 image config"
  exit 1
}
case $# in
1)
  IMAGE=${1}
  source ./harbor.cfg
  ;;
2)
  IMAGE=${1}
  shift
  source ${1}
  ;;
*)
  usage
esac
sudo crictl pull ${REGISTRY_URL}
