#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
if [ $# -lt 2 ];then
  echo "usage:${0} <client_pod> <server_pod> [--gdr]"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg

CLIENT_POD=${1}
SERVER_POD=${2}
NET_DEV=net1
RDMA_DEV=`${K8CL} exec ${CLIENT_POD} -- sh -c "./show_gids | grep -i ${NET_DEV} | grep v2 | grep -v fe80 | cut -f1"`
GID_IDX=`${K8CL} exec ${CLIENT_POD} -- sh -c "./show_gids | grep -i ${NET_DEV} | grep v2 | grep -v fe80 | cut -f3"`
IP=`${K8CL} exec ${SERVER_POD} -- sh -c "./show_gids | grep -i ${NET_DEV} | grep v2 | grep -v fe80 | cut -f5"`

GDR=false
for arg in "$@"; do
  case $arg in
    --gdr)
      GDR=true
      shift # Remove --gdr from processing
      ;;
    # Add more flags here as needed
  esac
done


if [ "${GDR}" == false ];then
  echo "--gdr flag not provided. Performing rdma perftest."
  echo "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a ${IP}"
  ${K8CL} exec ${CLIENT_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits  -p 123 -a ${IP}"
fi

if [ "${GDR}" == true ];then
  echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
  CUDA_DEV=`${K8CL} exec ${SERVER_POD} -- bash -c "./k8s-netdev-mapping.sh | grep ${NET_DEV} | cut -f 6"`
  BEST_GPU_LINK=`${K8CL} exec ${SERVER_POD} -- bash -c "./k8s-netdev-mapping.sh | grep ${NET_DEV} | cut -f 5"`
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest."
  ${K8CL} exec ${CLIENT_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a ${IP}"
fi