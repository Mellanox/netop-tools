#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
if [ $# -ne 2];then
  echo "usage:${0} client_pod server_pod"
  exit 1
fi
DEV=`kubectl exec ${1} -- sh -c "rdma link | grep net1| cut -d' ' -f2 | cut -d'/' -f1"`
IP=`kubectl exec ${2} -- sh -c "ip -br a show net1" | tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1`
kubectl exec ${1} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits ${IP}"
