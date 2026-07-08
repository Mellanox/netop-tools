#!/bin/bash
#
# patch the calico CIDR
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"
${K8CL} patch installation default --type=merge -p='{ "spec": { "calicoNetwork": { "mtu": 1400, "ipPools": [ { "cidr": "'${K8CIDR}'", "blockSize": 26, "encapsulation": "VXLANCrossSubnet", "natOutgoing": "Enabled", "nodeSelector": "all()" } ] } }}'
#Then restart:
${K8CL} rollout restart deployment calico-kube-controllers -n calico-system
${K8CL} rollout restart daemonset calico-node -n calico-system
#Verify:
${K8CL} get ippools -o wide
# Should show: ${K8CIDR}
