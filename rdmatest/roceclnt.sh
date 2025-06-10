#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
if [ $# -eq 3 ];then
  CLNT=${1}
  shift
  SRVR=${1}
  shift
  NET=${1}
  shift
elif [ $# -eq 2 ];then
  CLNT=${1}
  shift
  SRVR=${1}
  shift
  NET="net1"
else
  echo "usage:${0} client_pod server_pod {net[n]}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEV=$(${K8CL} exec ${CLNT} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ) {print $2 }}' | cut -d'/' -f1 )
IP=`${K8CL} exec ${SRVR} -- sh -c "ip -br a show ${NET}" | tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1`

${K8CL} exec ${CLNT} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits ${IP}"
