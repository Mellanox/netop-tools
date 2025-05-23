#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
NET="net1"
if [ $# -ne 2];then
  echo "usage:${0} client_pod server_pod"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEV=`${K8CL} exec ${1} -- sh -c "rdma link | grep ${NET}| cut -d' ' -f2 | cut -d'/' -f1"`
IP=`${K8CL} exec ${2} -- sh -c "ip -br a show ${NET}" | tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1`
${K8CL} exec ${1} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits ${IP}"
