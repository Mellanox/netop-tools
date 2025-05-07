#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
# ${3}=cuda device
#
if [ $# -ne 3 ];then
  echo "usage:${0} client_pod server_pod cuda_dev"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEV=`${K8CL} exec ${1} -- sh -c "rdma link | grep net2| cut -d' ' -f2 | cut -d'/' -f1"`
IP=`${K8CL} exec ${2} -- sh -c "ip -br a show net2" | tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1`
CUDA_DEV=${3}
# Marina says, don't use GID -x parametwer
#${K8CL} exec ${1} -- bash -c "ib_write_bw -x 2 -D 5  -d ${DEV} -F --report_gbits --use_cuda=2 ${IP}"

${K8CL} exec ${1} -- bash -c "ib_write_bw -D 5  -d mlx5_18 -F --report_gbits  -p 123  --use_cuda=${CUDA_DEV} ${IP}"
#${K8CL} exec ${1} -- bash -c "ib_write_bw -D 5  -d mlx5_18 -F --report_gbits  -p 123  ${IP}"
