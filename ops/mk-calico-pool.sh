#!/bin/bash
#
# patch the calico CIDR
#
source ${NETOP_ROOT_DIR}/globale_ops.cfg
kubectl patch installation default --type=merge -p='{ "spec": { "calicoNetwork": { "mtu": 1400, "ipPools": [ { "cidr": "'${K8CIDR}'", "blockSize": 26, "encapsulation": "VXLANCrossSubnet", "natOutgoing": "Enabled", "nodeSelector": "all()" } ] } }}'
#Then restart:
kubectl rollout restart deployment calico-kube-controllers -n calico-system
kubectl rollout restart daemonset calico-node -n calico-system
#Verify:
kubectl get ippools -o wide
# Should show: ${K8CIDR}
