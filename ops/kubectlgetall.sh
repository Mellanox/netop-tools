#!/bin/bash
#
#
#
function kubectlgetall {
for i in $(kubectl api-resources --verbs=list --namespaced -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq); do
  echo "Resource:" $i
  if [ -z "$1" ];then
    kubectl get --ignore-not-found ${i}
  else
    kubectl -n ${1} get --ignore-not-found ${i}
  fi
done
									}
