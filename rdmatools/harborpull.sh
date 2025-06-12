#!/bin/bash
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
#
#sudo apt install -y docker.io
DOCKER=`which docker`
PROJECT="nvidia"
REGISTRY="harbor.runailabs-ps.com/${PROJECT}"
IMAGE="rdmadbg_cuda"
sudo ${DOCKER} login ${REGISTRY}
sudo ${DOCKER} pull ${REGISTRY}/${IMAGE}:latest
