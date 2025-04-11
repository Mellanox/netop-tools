#!/bin/bash
#
#
if [ "$#" -lt 1 ];then
  echo "usage:$0 {NAMESPACE}"
  exit 1
fi
kubectl get Network-Attachment-Definitions -o yaml -n ${1}
