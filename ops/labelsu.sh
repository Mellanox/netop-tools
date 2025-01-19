#!/bin/bash
#
#
if [ $# -ne 2 ];then
  echo "usage:$0 {node-name} {key=value}"
  echo "example: $0 ub2204-worker1 node.su=su-1"
  exit 1
fi
kubectl label node ${1} "${2}"
