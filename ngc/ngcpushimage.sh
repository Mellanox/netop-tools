#!/bin/bash
#
# push an image to the private registry
#
if [ $# -lt 1 ];then
  echo "usage:$0 container:tag {team}"
  exit 1
fi
source ./env_DOCKER_HOST.sh
source ./ngc.cfg
source ./ngc_exec.sh
REGISTRY_IMAGE="${1}"
shift
REGISTRY_TEAM=${1:-"${REGISTRY_TEAM}"}
shift
URL=$(make_url)
sudo ${NGC} registry --debug image push ${URL}
