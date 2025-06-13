#!/bin/bash -x
#
# set up the server side rdma test
#
# ${1}=server pod
# ${2}={net[n]} device
#
NET_DEV="net1"
if [ $# -lt 1 ];then
  echo "usage:${0} server_pod --net {net[n]}"
  exit 1
fi
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
DEV=$(${K8CL} exec ${SRVR_POD} -- sh -c "rdma link" | awk --assign net="${NET}" '{ if ( $8 == net ){print $2 }}' | cut -d'/' -f1 )
${K8CL} exec ${SRVR_POD} -- bash -c "ib_write_bw -d ${DEV} -F --report_gbits"
