#!/bin/bash
#
# --creds "{username}:{password}"
#
source ./harbor.cfg
sudo crictl push --creds "${1}:${2}" ${HARBOR_URL}
