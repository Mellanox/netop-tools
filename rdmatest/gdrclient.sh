#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
function gid_info()
{
  awk --assign net="${1}" '{ if ( $7 == net ) {print $1, $2, $3, $4, $5, $6, $7 }}' | grep v2 | grep -v fe80
}
if [ $# -lt 2 ];then
  echo "usage:${0} <client_pod> <server_pod> --net <netdev> [--gdr]"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg

CLIENT_POD=${1}
shift
SERVER_POD=${1}
shift
NET_DEV=net1
GDR=false
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

GID_INFO=$(${K8CL} exec ${CLIENT_POD} -- sh -c "/root/show_gids" | gid_info ${NET_DEV})
RDMA_DEV=$(echo $GID_INFO |cut -d' ' -f1)
GID_IDX=$(echo $GID_INFO |cut -d' ' -f3)
GID_INFO=$(${K8CL} exec ${SERVER_POD} -- sh -c "/root/show_gids" | gid_info ${NET_DEV})
IP=$(echo $GID_INFO |cut -d' ' -f5)

if [ "${GDR}" == false ];then
  echo "--gdr flag not provided. Performing rdma perftest."
  echo "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a ${IP}"
  ${K8CL} exec ${CLIENT_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits  -p 123 -a ${IP}"
fi

if [ "${GDR}" == true ];then
  echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
  CUDA_DEV=`${K8CL} exec ${SERVER_POD} -- bash -c "/root/k8s-netdev-mapping.sh | grep ${NET_DEV} | cut -f 6"`
  BEST_GPU_LINK=`${K8CL} exec ${SERVER_POD} -- bash -c "/root/k8s-netdev-mapping.sh | grep ${NET_DEV} | cut -f 5"`
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest."
  ${K8CL} exec ${CLIENT_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a ${IP}"
fi
