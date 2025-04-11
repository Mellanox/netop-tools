#!/bin/bash
#
# copy RDMA tools to pod
#
POD="${1}"
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} cp ./get_rdma_dev.sh ${POD}:/root
${K8CL} cp ./ib_bw_test.sh ${POD}:/root
