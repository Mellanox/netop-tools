#!/bin/bash
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
#
#sudo apt install -y docker.io
sudo docker import rdmadbg_cuda_latest
IMAGE_ID=$(sudo docker images | grep -v "IMAGE" tr -s [:space:] | cut -d' ' -f3)
sudo docker tag ${IMAGE_ID} harbor.runailabs-ps.com/books/rdmadbg_cuda
sudo docker login harbor.runailabs-ps.com/books/
sudo docker pull harbor.runailabs-ps.com/books/rdmadbg_cuda
