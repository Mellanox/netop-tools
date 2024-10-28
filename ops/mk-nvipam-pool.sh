#!/bin/bash -xe
#
# define nvipam resources
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function nv_ippool()
{
cat <<POOLHEREDOC > ./ippool.yaml
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: IPPool
metadata:
# name: ${NETOP_NETWORK}
  name: ${NETOP_NETWORK_POOL}
  namespace: ${NETOP_NAMESPACE}
spec:
  subnet: ${NETOP_NETWORK_RANGE}
  perNodeBlockSize: ${NETOP_PERNODE_BLOCKSIZE}
  gateway: ${NETOP_NETWORK_GW}
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
        - key: node-role.kubernetes.io/worker
          operator: Exists
POOLHEREDOC
}
function configmap()
{
cat << CONFHEREDOC >./nv-ipam.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nvidia-k8s-ipam-config
  namespace: ${NETOP_NAMESPACE}
data:
  config: |
    {
      "pools": {
        "${NETOP_NETWORK_POOL}": {"subnet": ${NETOP_NETWORK_RANGE}, "perNodeBlockSize": ${NVNOP_PERNODE_BLOCKSIZE}, "gateway": ${NETOP_NETWORK_GW}}
      },
      "nodeSelector": {"kubernetes.io/os": "linux"}
    }
CONFHEREDOC
}
# Create CNI configuration
# 
# Example config for bridge CNI:
#
function cni_bridge()
{ 
cat <<CNIBRIDGEHEREDOC> /etc/cni/net.d/nv-ipam.d/10-${NETOP_NETWORK}.conf
{
    "cniVersion": "0.4.0",
    "name": "${NETOP_NETWORK}",
    "type": "bridge",
    "bridge": "mytestbr",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "nv-ipam",
        "poolName": "${NETOP_NETWORK_POOL}"
    }
}
CNIBRIDGEHEREDOC
}
function cni_ippool()
{
cat <<CNIHEREDOC> /etc/cni/net.d/nv-ipam.d/10-${NETOP_NETWORK_POOL}.conf
{
    "type": "nv-ipam",
    "poolName": "${NETOP_NETWORK_POOL}",
    "daemonSocket": "unix:///var/lib/cni/nv-ipam/daemon.sock",
    "daemonCallTimeoutSeconds": 5,
    "confDir": "/etc/cni/net.d/nv-ipam.d",
    "logFile": "/var/log/nv-ipam-cni.log",
    "logLevel": "info"
}
CNIHEREDOC
}
nv_ippool
#mkdir -p  /etc/cni/net.d/nv-ipam.d
#cni_ippool
