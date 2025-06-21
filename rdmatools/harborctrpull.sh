#!/bin/bash
#
# --creds "{username}:{password}"
#
source ./harbor.cfg
sudo ctr --namespace k8s.io images pull ${HARBOR_URL}
