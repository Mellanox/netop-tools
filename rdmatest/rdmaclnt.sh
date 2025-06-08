#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
# ${3}=RDMA net dev {net1|net2|net3|...}
# ${4}=RDMA|ROCE
#
if [ $# -ne 4];then
  echo "usage:${0} client_pod server_pod net_dev {RDMA|ROCE}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
CLNT=${1}
shift
SRVR=${1}
shift
NET=${1}
shift
MODE=${1}
shift
if [ "${MODE}" = "ROCE" ];then
  DEV=$(${K8CL} exec ${CLNT} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ) {print $2 }}' | cut -d'/' -f1 )
else
  DEV=$(${K8CL} exec ${CLNT} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ) {print $2 }}' )
fi
IP=$(${K8CL} exec ${SRVR} -- sh -c "ip -br a show ${NET}" | tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1 )
echo ${K8CL} exec ${CLNT} -- sh -c "ib_write_bw -d ${DEV} -F --report_gbits" ${IP}
