#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NODENAME} {SU}"
  exit 1
fi
kubectl label node ${1} node.su/${2}=""
