#!/bin/bash
#
#
if [ ! -d ./multus-cni ];then
  git clone https://github.com/k8snetworkplumbingwg/multus-cni.git
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
cd multus-cni
# We'll apply a YAML file with ${K8CL} from this repo, which installs the Multus components.
#
# Recommended installation:
#
cat ./deployments/multus-daemonset-thick.yml | ${K8CL} apply -f -

# See the thick plugin docs for more information about this architecture.
# 
# Alternatively, you may install the thin-plugin with:
# 
# cat ./deployments/multus-daemonset.yml | ${K8CL} apply -f -
