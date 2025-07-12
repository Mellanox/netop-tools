#!/bin/bash
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
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
sudo docker pull ${HARBOR_URL}
