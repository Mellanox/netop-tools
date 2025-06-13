#!/bin/bash
#
# --creds "{username}:{password}"
#
source ./harbor.cfg
sudo ctr images pull ${HARBOR_URL}
