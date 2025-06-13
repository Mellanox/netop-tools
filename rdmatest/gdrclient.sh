#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
function gid_info()
{
  gawk --assign net="${1}" '{ if ( $7 == net ) {print $1, $2, $3, $4, $5, $6, $7 }}' ${2} | grep v2 | grep -v fe80
}
if [ $# -lt 2 ];then
  echo "usage:${0} <client_pod> <server_pod> --net <netdev> [--gdr]"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg

CLNT_POD=${1}
shift
SRVR_POD=${1}
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

${K8CL} exec ${CLNT_POD} -- sh -c "/root/show_gids" > gid_info_clnt.$$
GID_INFO=$(gid_info ${NET_DEV} ./gid_info_clnt.$$)
RDMA_DEV=$(echo $GID_INFO |cut -d' ' -f1)
GID_IDX=$(echo $GID_INFO |cut -d' ' -f3)
${K8CL} exec ${SRVR_POD} -- sh -c "/root/show_gids" > gid_info_srvr.$$
GID_INFO=$(gid_info ${NET_DEV} gid_info_srvr.$$)
IP=$(echo $GID_INFO |cut -d' ' -f5)

if [ "${GDR}" == false ];then
  echo "--gdr flag not provided. Performing rdma perftest."
  echo "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a ${IP}"
  ${K8CL} exec ${CLNT_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits  -p 123 -a ${IP}"
fi

if [ "${GDR}" == true ];then
  echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
  ${K8CL} exec ${SRVR_POD} -- bash -c "/root/k8s-netdev-mapping.sh" > cuda_info.$$
  CUDA_DEV=$(grep ${NET_DEV}, cuda_info.$$| cut  -d',' -f6)
  BEST_GPU_LINK=$(grep ${NET_DEV}, cuda_info.$$| cut  -d',' -f5)
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest."
  ${K8CL} exec ${CLNT_POD} -- bash -c "ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a ${IP}"
fi
rm -f gid_info_clnt.$$ gid_info_srvr.$$
