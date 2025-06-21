#!/bin/bash
#
# --creds "{username}:{password}"
#
source ./harbor.cfg
sudo ctr --namespace k8s.io images push --user "${1}:${2}" ${HARBOR_URL}
