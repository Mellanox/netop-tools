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
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  NETWORKS=${NETWORKS},${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}
done
# trim leading ,
NETWORKS=`echo "${NETWORKS}" | sed 's/,//'`
cat << HEREDOC1 > ./${NAME}.yaml
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}
  annotations:
    k8s.v1.cni.cncf.io/networks: ${NETWORKS}
spec:
  containers:
  - name: appcntr1
    image: mellanox/rping-test
    imagePullPolicy: IfNotPresent
    securityContext:
      capabilities:
        add: ["IPC_LOCK"]
    resources:
      requests:
HEREDOC1
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
cat << HEREDOC2 >> ./${NAME}.yaml
        ${NETOP_RESOURCE_PATH}/${NETOP_RESOURCE}_${NIDX}: '1'
HEREDOC2
done
cat <<HEREDOC >> ./${NAME}.yaml
      limits:
HEREDOC
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
cat << HEREDOC3 >> ./${NAME}.yaml
        ${NETOP_RESOURCE_PATH}/${NETOP_RESOURCE}_${NIDX}: '1'
HEREDOC3
done
cat << HEREDOC4 >> ./${NAME}.yaml
    command:
    - sh
    - -c
    - sleep inf
HEREDOC4
if [ "${NODE}" != "" ];then
cat << NODEDOC >> ./${NAME}.yaml
  nodeSelector:
    # Note: Replace hostname or remove selector altogether
    kubernetes.io/hostname: ${NODE}
NODEDOC
fi
