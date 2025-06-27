#!/bin/bash -x
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
#
source ./harbor.cfg
#sudo apt install -y docker.io
#sudo docker import rdmadbg_cuda_latest
IMAGE_ID=$(sudo docker images | grep -v "IMAGE" | grep ${IMAGE} | tr -s [:space:] | cut -d' ' -f3)
sudo docker tag ${IMAGE_ID} ${HARBOR_URL}
sudo docker login ${HARBOR_REGISTRY}
sudo docker push ${HARBOR_URL}
