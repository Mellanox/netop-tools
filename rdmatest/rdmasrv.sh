#!/bin/bash
#
# set up the server side rdma test
#
# ${1}=server pod
# ${2}=RDMA net dev {net1|net2|net3|...}
# ${3}=RDMA|ROCE
#
if [ $# -lt 3 ];then
  echo "usage:${0} server_pod net_dev {RDMROCE}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
SRVR=${1}
shift
NET=${1}
shift
MODE=${1}
shift
if [ "${MODE}" = "ROCE" ];then
  DEV=$(${K8CL} exec ${SRVR} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ) {print $2 }}' | cut -d'/' -f1 )
else
  DEV=$(${K8CL} exec ${SRVR} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ) {print $2 }}' )
fi
echo ${K8CL} exec ${SRVR} -- sh -c "ib_write_bw -d ${DEV} -F --report_gbits" 
