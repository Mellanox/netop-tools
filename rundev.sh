#!/bin/bash
#
# the flow for creating a dev environment
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
DEVPOLICY="nic-cluster-policy.yaml"
# get the current policy if not defined
if [ ! -f ${DEVPOLICY} ];then
  ${K8CL} get NicClusterPolicy nic-cluster-policy -o yaml > ${DEVPOLICY}
  ./uninstall-network-operator.sh
fi
# Delete all of the Meta data except name:
# Delete all of status
python3 edityaml.py ${DEVPOLICY} > ${DEVPOLICY}.dev
${K8CL} create ns ${NETOP_NAMESPACE}
make run
# Then apply policy ${DEVPOLICY}
${K8CL} apply -f ${DEVPOLICY}.dev
