#!/bin/bash
#
# ${1}=client pod
# ${2}=target server pod
#
NET_DEV="net1"
if [ $# -lt 2 ];then
  echo "usage:${0} client_pod server_pod --net {net[n]}"
  exit 1
fi
CLNT_POD=${1}
shift
SRVR_POD=${1}
shift
for arg in "$@"; do
  case $arg in
    --net)
      shift # Remove --net from processing
      NET_DEV=${1}
      ;;
    # Add more flags here as needed
  esac
done
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEV=$(${K8CL} exec ${CLNT_POD} -- sh -c "rdma link" | awk --assign net="${NET_DEV}" '{ if ( $8 == net ) {print $2 }}' | cut -d'/' -f1 )
IP=$(${K8CL} exec ${SRVR_POD} -- sh -c "ip -br a show ${NET_DEV}" | tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1)

${K8CL} exec ${CLNT_POD} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits ${IP}"
