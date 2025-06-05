#!/bin/bash
#
# set up the server side rdma test
#
# ${1}=server pod
#
NET="net1"
if [ $# -lt 1 ];then
  echo "usage:${0} server_pod"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEV=$(${K8CL} exec ${1} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ){print $2 }}' | cut -d'/' -f1 )
${K8CL} exec ${1} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits"
