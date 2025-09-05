#!/bin/bash
#
# pod.yaml configuration file for such a deployment:
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function usage()
{
  echo "usage:$0 {podname} {app namespace}"
  echo "usage:$0 {podname} {app namespace} {worker node}"
  exit 1
}
function set_gpus
{
if [ "${NUM_GPUS}" != "" ] && [ "${NUM_GPUS}" -gt 0 ];then
cat << HEREDOC0
        nvidia.com/gpu: '${NUM_GPUS}'
HEREDOC0
fi
}
function get_networks()
{
for NETOP_SU in ${NETOP_SULIST[@]};do
  for DEVDEF in ${NETOP_NETLIST[@]};do
    NIDX=`echo ${DEVDEF}|cut -d',' -f1`
    NETWORKS=${NETWORKS},${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}
  done
done
# trim leading ,
NETWORKS=`echo "${NETWORKS}" | sed 's/,//'`
}
function set_network_resource()
{
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
cat << HEREDOC2 
        ${NETOP_RESOURCE_PATH}/${NETOP_RESOURCE}_${NIDX}: '1'
HEREDOC2
done
}
NAME=${1}
shift
NETOP_APP_NAMESPACE=${1:-'default'}
shift
NODE=${1}
shift
if [ "${NAME}" = "" ];then
  usage
fi
mkdir -p apps
cd apps
get_networks
cat << HEREDOC1 > ./${NAME}.yaml
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}
  annotations:
    k8s.v1.cni.cncf.io/networks: ${NETWORKS}
  namespace: ${NETOP_APP_NAMESPACE}
spec:
  containers:
  - name: appcntr1
    #image: mellanox/rping-test
    image: harbor.runailabs-ps.com/netop/rdmadbg_cuda_x86_64:latest
    imagePullPolicy: IfNotPresent
    env:
       - name: SYSCTL_CONFIG
         value: "${SYSCTL_CONFIG}"
    securityContext:
      privileged: true
      capabilities:
        add: ["IPC_LOCK"]
    resources:
      requests:
HEREDOC1
set_gpus >> ./${NAME}.yaml
set_network_resource >> ./${NAME}.yaml
cat <<HEREDOC3 >> ./${NAME}.yaml
      limits:
HEREDOC3
set_gpus >> ./${NAME}.yaml
set_network_resource >> ./${NAME}.yaml
cat << HEREDOC5 >> ./${NAME}.yaml
    command:
    - sh
    - -c
    - sleep inf
HEREDOC5
if [ "${NODE}" != "" ];then
cat << NODEDOC >> ./${NAME}.yaml
  nodeSelector:
    # Note: Replace hostname or remove selector altogether
    kubernetes.io/hostname: ${NODE}
NODEDOC
fi
