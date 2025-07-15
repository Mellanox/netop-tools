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
  RP_FILTER="sysctl net.ipv4.conf.all.rp_filter=0"
  ARP_ANNOUNCE="sysctl net.ipv4.conf.all.arp_announce=2"
  ARP_IGNORE="sysctl net.ipv4.conf.all.arp_ignore=1"
  if [ "${GDR}" == false ];then
    echo "${RP_FILTER};${ARP_ANNOUNCE};${ARP_IGNORE};ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 -a ${IP}"
  else
    echo "${RP_FILTER};${ARP_ANNOUNCE};${ARP_IGNORE};ib_write_bw -d ${RDMA_DEV} -F -x ${GID_IDX} --report_gbits -p 123 --use_cuda=${CUDA_DEV} -a ${IP}"
  fi
}
if [ $# -lt 2 ];then
  echo "usage:${0} <client_pod> <server_pod> --net <netdev> [ --ns <namespace> ] [--gdr] "
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
    --ns)                                                                                               │
      shift # Remove --ns from processing                                                               │
      NAMESPACE="-n ${1}"                                                                               │
      shift   
    # Add more flags here as needed
  esac
done
GID_INFO_FILE_SRVR="/tmp/gid_info_srvr.$$"
GID_INFO_FILE_CLNT="/tmp/gid_info_clnt.$$"
CUDA_INFO_FILE="/tmp/cuda_info.$$"

${K8CL} ${NAMESPACE} exec ${CLNT_POD} -- sh -c "/root/show_gids" > ${GID_INFO_FILE_CLNT}
GID_INFO=$(gid_info ${NET_DEV} ${GID_INFO_FILE_CLNT})
RDMA_DEV=$(echo $GID_INFO |cut -d' ' -f1)
GID_IDX=$(echo $GID_INFO |cut -d' ' -f3)
${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- sh -c "/root/show_gids" > ${GID_INFO_FILE_SRVR}
GID_INFO=$(gid_info ${NET_DEV} ${GID_INFO_FILE_SRVR})
IP=$(echo $GID_INFO |cut -d' ' -f5)

if [ "${GDR}" == false ];then
  echo "--gdr flag not provided. Performing rdma perftest."
  CMDSTR=$(get_cmdstr)
  ${K8CL} ${NAMESPACE} exec ${CLNT_POD} -- bash -c "${CMDSTR}"
  echo "${CLNT_POD}:${NET_DEV}:${CMDSTR}"
fi

if [ "${GDR}" == true ];then
  echo "--gdr flag Provided. Determining optimal CUDA device. This may take a few seconds ..."
  ${K8CL} ${NAMESPACE} exec ${SRVR_POD} -- bash -c "/root/k8s-netdev-mapping.sh" > ${CUDA_INFO_FILE}
  CUDA_DEV=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f6)
  BEST_GPU_LINK=$(grep ${NET_DEV}, ${CUDA_INFO_FILE}| cut  -d',' -f5)
  echo "Using CUDA device ${CUDA_DEV} via ${BEST_GPU_LINK}. Performing GDR perftest."
  CMDSTR=$(get_cmdstr)
  ${K8CL} ${NAMESPACE} exec ${CLNT_POD} -- bash -c "${CMDSTR}"
  echo "${CLNT_POD}:${NET_DEV}:${CMDSTR}"
fi
rm -f ${GID_INFO_FILE_CLNT} ${GID_INFO_FILE_SRVR} ${CUDA_INFO_FILE}
