#!/bin/bash
#
# set up the server side rdma test
#
# ${1}=server pod
#
if [ $# -lt 2 ];then
  echo "usage:${0} server_pod {RDMA|ROCE}"
  exit 1
fi
if [ "${2}" = "ROCE" ];then
  DEV=`kubectl exec ${1} -- sh -c "rdma link | grep net1| cut -d' ' -f2 | cut -d'/' -f1"`
else
  DEV=`kubectl exec ${1} -- sh -c "rdma link | grep net1| cut -d' ' -f2"`
fi
echo kubectl exec ${1} -- sh -c "ib_write_bw -d ${DEV} -F --report_gbits"     # rocep177s0f0v7  is the server listen device
