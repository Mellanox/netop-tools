#!/bin/bash
#
# set up the server side rdma test
#
function gid_info()
{
  gawk --assign net="${1}" '{ if ( $7 == net ) {print $1, $2, $3, $4, $5, $6, $7 }}' | grep v2 | grep -v fe80
}
function get_cmdstr() 
{
#  RP_FILTER="sysctl net.ipv4.conf.all.rp_filter=0"
#  ARP_ANNOUNCE="sysctl net.ipv4.conf.all.arp_announce=2"
#  ARP_IGNORE="sysctl net.ipv4.conf.all.arp_ignore=1"
  if [ "${GDR}" == false ];then
    echo "/root/sysctl_config.sh;ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a ${SIZE}" 
  else
    echo "/root/sysctl_config.sh;ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a ${SIZE}"
  fi
}
function roce_config()
{
  CUDA_INFO_FILE="/tmp/cuda_info.$$"
  GID_INFO=$(${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- sh -c "/root/show_gids" | gid_info ${NET_DEV})
  RDMA_DEV=$(echo ${GID_INFO} |cut -d' ' -f1)
  GID_IDX=$(echo ${GID_INFO} |cut -d' ' -f3)
}
function ib_config()
{
  CUDA_INFO_FILE="/tmp/cuda_info.$$"
  GID_INFO=$(${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- sh -c "/root/getrdmanet.sh ${NET_DEV}" )
  RDMA_DEV=$(echo ${GID_INFO} |cut -d',' -f1)
  GID_IDX=$(echo ${GID_INFO} |cut -d',' -f2)
}
if [ $# -lt 1 ];then
  echo "usage:${0} <roce|ib> <server_pod> --net <netdev> [ --ns <namespace> ] --size [block size in bytes] [--gdr]|[--gpu {n}]  "
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg

MODE=${1}
shift
SRVR_POD=${1}
shift

GDR=false
NET_DEV="net1"
CUDA_DEV=""
SIZE=""
for arg in "$@"; do
  case $arg in
  --gdr)
    GDR=true
    shift # Remove --gdr from processing
    ;;
  --net)
    shift # Remove --net from processing
    NET_DEV=${1}
    shift
    ;;
  --ns)
    shift # Remove --ns from processing
    NAMESPACE="-n ${1}"
    shift
    ;;
  --gpu)
    shift # Remove --gpu from processing
    CUDA_DEV="${1}"
    GDR=true
    BEST_GPU_LINK="manual"
    shift
    ;;
  --size)
    shift # remove --size
    SIZE=" -s ${1}"
    shift
    ;;
    # Add more flags here as needed
  *)
    echo "invalid arg:$arg"
    usage
    exit 1
  esac
done

case ${MODE} in
roce)
  roce_config
  ;;
ib)
  ib_config
  ;;
esac
if [ "${GDR}" == false ];then
  echo "--gdr flag not provided. Performing rdma perftest. Waiting for client to connect ..."
  CMDSTR=$(get_cmdstr)
  echo "${SRVR_POD}:${NET_DEV}:${CMDSTR}"
  ${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- bash -c "${CMDSTR}"
  echo "${SRVR_POD}:${NET_DEV}:${CMDSTR}"
fi

if [ "${GDR}" == true ];then
  if [ "${CUDA_DEV}" == "" ];then
    echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
    ${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- bash -c "/root/k8s-netdev-mapping.sh" > ${CUDA_INFO_FILE}
    CUDA_DEV=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f6)
    BEST_GPU_LINK=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f5)
  fi
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest. Waiting for client to connect ..."
  CMDSTR=$(get_cmdstr)
  echo "${SRVR_POD}:${NET_DEV}:${CMDSTR}"
  ${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- bash -c "${CMDSTR}"
  echo "${SRVR_POD}:${NET_DEV}:${CMDSTR}"
fi
rm -f ${CUDA_INFO_FILE}
