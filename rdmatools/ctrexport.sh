#!/bin/bash
#
#
#
IMAGE=${1}
shift
FILE=${1}
shift
sudo ctr -n k8s.io images export ${FILE} ${IMAGE}
