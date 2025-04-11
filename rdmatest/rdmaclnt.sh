#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
if [ $# -ne 2];then
  echo "usage:${0} client_pod server_pod {RDMA|ROCE}"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
if [ "${2}" = "ROCE" ];then
  DEV=`${K8CL} exec ${1} -- sh -c "rdma link | grep net1| cut -d' ' -f2 | cut -d'/' -f1"`
else
  DEV=`${K8CL} exec ${1} -- sh -c "rdma link | grep net1| cut -d' ' -f2"`
fi
IP=`${K8CL} exec ${2} -- sh -c "ip -br a show net1" | tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1`
echo ${K8CL} exec ${1} -- sh -c "ib_write_bw -d ${DEV} -F --report_gbits" ${IP}
