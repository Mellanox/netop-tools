#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
function gid_info()
{
  gawk --assign net="${1}" '{ if ( $7 == net ) {print $1, $2, $3, $4, $5, $6, $7 }}' ${2} | grep v2 | grep -v fe80
}
function get_cmdstr()
{
#  RP_FILTER="sysctl net.ipv4.conf.all.rp_filter=0"
#  ARP_ANNOUNCE="sysctl net.ipv4.conf.all.arp_announce=2"
#  ARP_IGNORE="sysctl net.ipv4.conf.all.arp_ignore=1"
  raw_frames
  if [ "${GDR}" == false ];then
    echo "/root/sysctl_config.sh;ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a ${IP} ${SIZE}"
  else
    echo "/root/sysctl_config.sh;ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a ${IP} ${SIZE}"
  fi
}
function roce_config()
{
  # Get RDMA device and GID index from client pod
  ${K8CL} ${NAMESPACE} exec ${CLNT_POD} -- sh -c "/root/show_gids" > ${GID_INFO_FILE_CLNT}
  GID_INFO=$(gid_info ${NET_DEV} ${GID_INFO_FILE_CLNT})
  RDMA_DEV=$(echo ${GID_INFO} |cut -d' ' -f1)
  GID_IDX=$(echo ${GID_INFO} |cut -d' ' -f3)
  
  # Get server IP using ip command instead of gid_info
  # ip -br a show dev net1 outputs: "net1@if123  UP  192.168.0.33/24 fe80::xxx/64"
  IP=$(${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- sh -c "ip -br a show dev ${NET_DEV}" | awk '{print $3}' | cut -d'/' -f1 | grep -v '^fe80')
}
function ib_config()
{
  CUDA_INFO_FILE="/tmp/cuda_info.$$"
  GID_INFO=$(${K8CL} ${NAMESPACE} exec ${CLNT_POD} -- sh -c "/root/getrdmanet.sh ${NET_DEV}" )
  RDMA_DEV=$(echo ${GID_INFO} |cut -d',' -f1)
  GID_IDX=$(echo ${GID_INFO} |cut -d',' -f2)
  GID_INFO=$(${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- sh -c "/root/getrdmanet.sh ${NET_DEV}" )
  IP=$(echo ${GID_INFO} |cut -d',' -f3)
}
#
# -F = Raw Ethernet mode - sends raw Ethernet frames, bypassing the normal RoCE stack. This mode:
# Requires special driver support
# Often doesn't work with VFs (Virtual Functions)
# Needs specific permissions/capabilities
# For RoCEv2 over VFs, don't use -F. Standard RoCE mode works correctly:
#
function raw_frames()
{
case ${USECASE} in
sriovnet_rdma|sriovinbet_rdma|hostdev_rdma_sriov)
  RAWFRAMES=""
  ;;
*)
  RAWFRAMES="-F"
  ;;
esac
}
function usage()
{
  echo "usage:${0} <ib|roce> <client_pod> <server_pod> --net <netdev> [ --ns <namespace> ] --size [block size in bytes] [--gdr]|[--gpu [n] "
}
if [ $# -lt 2 ];then
  usage
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg

MODE=${1}
shift
CLNT_POD=${1}
shift
SRVR_POD=${1}
shift
NET_DEV=net1
GDR=false
CUDA_DEV=""
SIZE=""
while [ $# -gt 0 ]; do
  arg=${1}
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
GID_INFO_FILE_SRVR="/tmp/gid_info_srvr.$$"
GID_INFO_FILE_CLNT="/tmp/gid_info_clnt.$$"
CUDA_INFO_FILE="/tmp/cuda_info.$$"

case ${MODE} in
roce)
  roce_config
  ;;
ib)
  ib_config
  ;;
esac

if [ "${GDR}" == false ];then
  echo "--gdr flag not provided. Performing rdma perftest."
  CMDSTR=$(get_cmdstr)
  ${K8CL} ${NAMESPACE} exec ${CLNT_POD} -- bash -c "${CMDSTR}"
  echo "${CLNT_POD}:${NET_DEV}:${CMDSTR}"
fi

if [ "${GDR}" == true ];then
  if [ "${CUDA_DEV}" == "" ];then
    echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
    ${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- bash -c "/root/k8s-netdev-mapping.sh" > ${CUDA_INFO_FILE}
    CUDA_DEV=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f6)
    BEST_GPU_LINK=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f5)
  fi
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest."
  CMDSTR=$(get_cmdstr)
  ${K8CL} ${NAMESPACE} exec ${CLNT_POD} -- bash -c "${CMDSTR}"
  echo "${CLNT_POD}:${NET_DEV}:${CMDSTR}"
fi
rm -f ${GID_INFO_FILE_CLNT} ${GID_INFO_FILE_SRVR} ${CUDA_INFO_FILE}
