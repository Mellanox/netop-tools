#!/bin/bash -x
#
# set up the server side rdma test
#
# ${1}=server pod
# ${2}={net[n]} device
#
if [ $# -eq 2 ];then
  SRVR=${1}
  shift
  NET=${1}
  shift
elif [ $# -eq 1 ];then
  SRVR=${1}
  shift
  NET="net1"
else
  echo "usage:${0} client_pod {net[n]}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEV=$(${K8CL} exec ${SRVR} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ){print $2 }}' | cut -d'/' -f1 )
${K8CL} exec ${SRVR} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits"
