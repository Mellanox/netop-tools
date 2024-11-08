#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NODENAME}"
  exit 1
fi
kubectl label node ${1} node-role.kubernetes.io/worker-
