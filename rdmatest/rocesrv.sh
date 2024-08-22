#!/bin/bash -x
#
# set up the server side rdma test
#
# ${1}=server pod
#
if [ $# -lt 1 ];then
  echo "usage:${0} server_pod"
  exit 1
fi
DEV=`kubectl exec ${1} -- sh -c "rdma link | grep net1| cut -d' ' -f2 | cut -d'/' -f1"`
kubectl exec ${1} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits"
# rocep177s0f0v7  is the server listen device
