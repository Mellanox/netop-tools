#!/bin/bash
#
# setup the docker login to the ClustermMODS ngc private registry.
# this requires a person_access_token from the ${REGISTRY} environment
#
source ./env_DOCKER_HOST.sh
source ./ngc.cfg
if [ $# -eq 1 ];then
  cat ${1} | docker login ${REGISTRY} -u '$oauthtoken' --password-stdin
else
  docker login ${REGISTRY} -u '$oauthtoken'
fi
