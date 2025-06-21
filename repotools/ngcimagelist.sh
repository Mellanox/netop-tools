#!/bin/bash
#
# get the list of doca driver containers from nvidia 
#
#
REG="nvcr.io/nvidia/mellanox"
IMAGE=doca-driver
NGC_API_TOKEN="{NGC_API_TOKEN}"
#curl -s https://nvcr.io/v2/nvidia/tags/list | jq -r '.tags[]'
#docker login --username '$oauthtoken' nvcr.io
#curl -s -u '$oauthtoken':${NGC_API_TOKEN} https://nvcr.io/v2/nvidia/tags/list
curl --user '$oauthtoken' https://nvcr.io/v2/nvidia/tags/list
#docker image doca-driver
