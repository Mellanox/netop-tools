#!/bin/bash -x
#
#
IMAGE=${1}
source harbor.cfg
LATEST="${HARBOR_IMAGE}_latest"
chmod +x *.sh show_gids ib_top
sudo docker build -t ${HARBOR_REGISTRY}/${HARBOR_IMAGE} -f Dockerfile.${IMAGE} . > docker.log 2>&1
if [ $? != 0 ];then
  echo "usage:$0 Dockerfile.{rdmadbg|rdmadbg_cuda}"
  exit 1
fi
CTR=$(which ctr)
if [ "${CTR}" = "" ];then
  echo "missing ctr tool in '$PATH'"
  echo "default location is /usr/bin/ctr" 
  echo "but location depends on node installation configuration"
  exit 1
fi
( sudo docker save ${HARBOR_URL} > ${LATEST}  ) 2>>docker.log
sudo ctr --namespace=k8s.io image import ${LATEST} >> docker.log 2>&1
SHA256=$(cat docker.log | grep "writing image" | cut -d' ' -f5 | cut -d: -f2)
IMAGE_ID=${SHA256:0:12}
sudo docker tag ${IMAGE_ID} ${HARBOR_URL}
#sudo docker rmi ${HARBOR_URL}
