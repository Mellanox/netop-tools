#!/bin/bash
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${HELMCL} repo add nvidia https://helm.ngc.nvidia.com/nvidia
${HELMCL} repo update
${HELMCL} install network-operator nvidia/network-operator -n ${NETOP_NAMESPACE} --create-namespace --version ${NETOP_VERSION} --set sriovNetworkOperator.enabled=true --wait
