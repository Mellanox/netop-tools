#!/bin/bash
#
# labe a docker iumage to match the ngc registry structure
#
if [ $# -lt 1 ];then
  echo "usage:$0 {docker_image_id} container:tag {team}"
  exit 1
fi
source ./env_DOCKER_HOST.sh
source ./ngc.cfg
source ./ngc_exec.sh
IMAGE_ID="${1}"
shift
REGISTRY_IMAGE="${1}"
shift
REGISTRY_TEAM=${1:-"${REGISTRY_TEAM}"}
shift
URL=$(make_url)
echo sudo docker tag "${IMAGE_ID}" "${URL}"
sudo docker tag ${IMAGE_ID} ${URL}
