#!/bin/bash -x
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
#
#sudo apt install -y docker.io
DOCKER=`whick docker`
PROJECT="nvidia"
REGISTRY="harbor.runailabs-ps.com/${PROJECT}"
IMAGE="rdmadbg_cuda"
sudo ${DOCKER} login ${REGISTRY}
sudo ${DOCKER} image pull ${REGISTRY}/rdmadbg_cuda:latest
