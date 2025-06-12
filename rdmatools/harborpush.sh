#!/bin/bash -x
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
#
#sudo apt install -y docker.io
#sudo docker import rdmadbg_cuda_latest
PROJECT="nvidia"
REGISTRY="harbor.runailabs-ps.com/${PROJECT}"
IMAGE="rdmadbg_cuda"
#IMAGE_ID=$(sudo docker images | grep -v "IMAGE" | grep ${IMAGE} | tr -s [:space:] | cut -d' ' -f3)
#sudo docker tag ${IMAGE_ID} ${REGISTRY}/rdmadbg_cuda
sudo docker login ${REGISTRY}
sudo docker push ${REGISTRY}/rdmadbg_cuda:latest
