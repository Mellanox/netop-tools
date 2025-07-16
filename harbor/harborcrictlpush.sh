#!/bin/bash
#
# --creds "{username}:{password}"
#
function usage()
{
  echo "usage:$0 user passwd image config"
  echo "usage:$0 user passwd image # use harbor.cfg defaults"
  exit 1
}
if [ $# -lt 3 ];then
  usage
fi
USR="${1}"
shift
PSW="${1}"
shift
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
sudo crictl push --creds "${USR}:${PSW}" ${REGISTRY_URL}
