#!/bin/bash
#
# https://stackoverflow.com/questions/46419163/what-will-happen-to-evicted-pods-in-kubernetes
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} get pods --all-namespaces -o json | jq '.items[] | select(.status.reason!=null) | select(.status.reason | contains("Evicted")) | "kubectl delete pods \(.metadata.name) -n \(.metadata.namespace)"' | xargs -n 1 bash -c
