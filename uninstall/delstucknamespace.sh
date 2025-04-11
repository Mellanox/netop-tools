#!/bin/bash
#
# remove a namespace stuck in terminating
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
#curl -k -H "Content-Type: application/json" -X PUT --data-binary @tmp.json http://127.0.0.1:8001/api/v1/namespaces/network-operator/finalize
#${K8CL} api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n network-operator
${K8CL} get namespace "${1}" -o json \
  | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/" \
  | ${K8CL} replace --raw /api/v1/namespaces/${1}/finalize -f -
