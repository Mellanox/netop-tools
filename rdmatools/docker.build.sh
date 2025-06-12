#!/bin/bash
#
#
IMAGE=${1}
REGISTRY="harbor.runailabs-ps.com/nvidia"
chmod +x *.sh show_gids ib_top
docker build -t ${REGISTRY}/${IMAGE} -f Dockerfile.${1} .
if [ $? != 0 ];then
  echo "usage:$0 Dockerfile.{rdmadbg|rdmadbg_cuda}"
  exit 1
fi
CTR=$(which ctr)
if [ "${CTR}" = "" ];then
  echo "missing ctr tool in '$PATH'"
  echo "default location is /usr/bin/ctr" 
  echo "but location depends on node installtion configuratio"
  exit 1
fi
docker save ${REGISTRY}/${IMAGE}:latest > ${IMAGE}_latest
#ctr --namespace=k8s.io image import ${IMAGE}_latest
ctr --namespace=k8s.io image import ${IMAGE}_latest
#docker rmi ${IMAGE}:latest
