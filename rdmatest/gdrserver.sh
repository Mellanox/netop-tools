#!/bin/bash
#
# set up the server side rdma test
#
# ${1}=server pod
# ${2}=net_dev (net1,net2,net3,net4,...)
#
if [ $# -lt 2 ];then
  echo "usage:${0} <server_pod> <net_dev> [--gdr]"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
SERVER_POD=${1}
shift
NET_DEV=${1}
shift
RDMA_DEV=`${K8CL} exec ${SERVER_POD} -- sh -c "rdma link | grep ${NET_DEV}| cut -d' ' -f2 | cut -d'/' -f1"`

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
  ${K8CL} exec ${SERVER_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F --report_gbits -p 123"
fi

if [ "${GDR}" == true ];then
  echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
  CUDA_DEV=`${K8CL} exec ${SERVER_POD} -- bash -c "./k8s-netdev-mapping.sh | grep ${NET_DEV} | tail -1 | cut -d ' ' -f7"`
  BEST_GPU_LINK=`${K8CL} exec ${SERVER_POD} -- bash -c "./k8s-netdev-mapping.sh | grep ${NET_DEV} | tail -2 | head -1 | cut -d ' ' -f6"`
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest. Waiting for client to connect ..."
  ${K8CL} exec ${SERVER_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F --report_gbits -p 123 --use_cuda=${CUDA_DEV}"
fi
