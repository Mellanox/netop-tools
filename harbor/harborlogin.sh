#!/bin/bash -x
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
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
IMAGE_ID=$(sudo docker images | grep -v "IMAGE" | grep ${IMAGE} | tr -s [:space:] | cut -d' ' -f3)
sudo docker tag ${IMAGE_ID} ${HARBOR_URL}
sudo docker login ${HARBOR_REGISTRY}
sudo docker push ${HARBOR_URL}
