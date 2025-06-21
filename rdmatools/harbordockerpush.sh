#!/bin/bash -x
#
# from deliotte bastion node, was able to login.
#
# creds in pwsafe usb
#
source ./harbor.cfg
#sudo apt install -y docker.io
sudo docker login ${HARBOR_REGISTRY}
sudo docker push ${HARBOR_URL}
