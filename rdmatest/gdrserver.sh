#!/bin/bash
#
# set up the server side rdma test
#
# ${1}=server pod
#
if [ $# -lt 2 ];then
  echo "usage:${0} server_pod cuda_device"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEV=`${K8CL} exec ${1} -- sh -c "rdma link | grep net2| cut -d' ' -f2 | cut -d'/' -f1"`
CUDA_DEV=${2}
# Marina says, don't use -x GID option
#${K8CL} exec ${1} -- bash -c "ib_write_bw -d ${DEV} -x 2 -F --report_gbits"

${K8CL} exec ${1} -- bash -c "ib_write_bw -d mlx5_33 -F --report_gbits -p 123 --use_cuda=${CUDA_DEV}"
#${K8CL} exec ${1} -- bash -c "ib_write_bw -d mlx5_33 -F --report_gbits -p 123"
#${K8CL} exec ${1} -- bash -c "ib_write_bw -d ${DEV}  -F --report_gbits"
