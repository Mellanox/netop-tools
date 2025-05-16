#!/bin/bash
#
# set up the server side rdma test
#
# ${1}=server pod
#
if [ $# -lt 1 ];then
  echo "usage:${0} <server_pod> [--gdr]"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg

SERVER_POD=${1}
NET_DEV=net1
RDMA_DEV=`${K8CL} exec ${SERVER_POD} -- sh -c "./show_gids | grep -i ${NET_DEV} | grep v2 | grep -v fe80 | cut -f1"`
GID_IDX=`${K8CL} exec ${SERVER_POD} -- sh -c "./show_gids | grep -i ${NET_DEV} | grep v2 | grep -v fe80 | cut -f3"`


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
  echo "--gdr flag not provided. Performing rdma perftest. Waiting for client to connect ..."
  echo "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a"
  ${K8CL} exec ${SERVER_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a"
fi

if [ "${GDR}" == true ];then
  echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
  CUDA_DEV=`${K8CL} exec ${SERVER_POD} -- bash -c "./k8s-netdev-mapping.sh | grep ${NET_DEV} | cut -f 6"`
  BEST_GPU_LINK=`${K8CL} exec ${SERVER_POD} -- bash -c "./k8s-netdev-mapping.sh | grep ${NET_DEV} | cut -f 5"`
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest. Waiting for client to connect ..."
  ${K8CL} exec ${SERVER_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a"
fi