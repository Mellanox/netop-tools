#!/bin/bash
#
# --creds "{username}:{password}"
#
function usage()
{
  echo "docker login to harbor required"
  echo "usage:$0 image config"
  echo "usage:$0 image # use harbor.cfg defaults"
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
sudo ctr --namespace k8s.io images pull ${REGISTRY_URL}
