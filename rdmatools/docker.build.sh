#!/bin/bash
#
#
IMAGE=${1}
docker build -t ${IMAGE} -f Dockerfile.${1} .
if [ $? != 0 ];then
  exit 1
fi
docker save ${IMAGE}:latest > ${IMAGE}_latest
#ctr --namespace=k8s.io image import ${IMAGE}_latest
./nerdctlload.sh ${IMAGE}_latest
docker rmi ${IMAGE}:latest
