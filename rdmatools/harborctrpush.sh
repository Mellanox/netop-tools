#!/bin/bash
#
# --creds "{username}:{password}"
#
source ./harbor.cfg
sudo ctr images push --user "${1}:${2}" ${HARBOR_URL}
