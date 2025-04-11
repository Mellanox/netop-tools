#!/bin/bash
#
#
#
function ${K8CL}getall {
for i in $(${K8CL} api-resources --verbs=list --namespaced -o name | grep -v "events.events.k8s.io" | grep -v "events" | sort | uniq); do
  echo "Resource:" $i
  if [ -z "$1" ];then
    ${K8CL} get --ignore-not-found ${i}
  else
    ${K8CL} -n ${1} get --ignore-not-found ${i}
  fi
done
}
