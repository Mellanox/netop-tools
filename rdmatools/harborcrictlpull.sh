#!/bin/bash
#
# --creds "{username}:{password}"
#
source ./harbor.cfg
#sudo crictl pull --creds "${1}:${2}" ${HARBOR_URL}
sudo crictl pull ${HARBOR_URL}
