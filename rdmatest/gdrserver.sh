#!/bin/bash
#
# set up the server side rdma test
#
function gid_info()
{
  gawk --assign net="${1}" '{ if ( $7 == net ) {print $1, $2, $3, $4, $5, $6, $7 }}' | grep v2 | grep -v fe80
}
if [ $# -lt 1 ];then
  echo "usage:${0} <server_pod> --net <netdev> [--gdr]"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg

SERVER_POD=${1}
shift

GDR=false
NET_DEV="net1"
for arg in "$@"; do
  case $arg in
    --gdr)
      GDR=true
      shift # Remove --gdr from processing
      ;;
    --net)
      shift # Remove --net from processing
      NET_DEV=${1}
      ;;
    # Add more flags here as needed
  esac
done

CUDA_INFO_FILE="/tmp/cuda_info.$$"

GID_INFO=$(${K8CL} exec ${SERVER_POD} -- sh -c "/root/show_gids" | gid_info ${NET_DEV})
RDMA_DEV=$(echo $GID_INFO |cut -d' ' -f1)
GID_IDX=$(echo $GID_INFO |cut -d' ' -f3)

if [ "${GDR}" == false ];then
  echo "--gdr flag not provided. Performing rdma perftest. Waiting for client to connect ..."
  echo "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a"
  ${K8CL} exec ${SERVER_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a"
fi

if [ "${GDR}" == true ];then
  echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
  ${K8CL} exec ${SERVER_POD} -- bash -c "/root/k8s-netdev-mapping.sh" > ${CUDA_INFO_FILE}
  CUDA_DEV=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f6)
  BEST_GPU_LINK=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f5)
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest. Waiting for client to connect ..."
  ${K8CL} exec ${SERVER_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a"
fi
rm -f ${CUDA_INFO_FILE}
