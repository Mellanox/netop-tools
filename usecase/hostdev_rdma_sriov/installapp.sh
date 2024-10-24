#!/bin/bash
#
# pod.yaml configuration file for such a deployment:
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

NAME=${1}
shift
NODE=${1}
shift
if [ "${NAME}" = "" ];then
	echo "usage:$0 {podname}"
	echo "usage:$0 {podname} {worker node}"
	exit 1
fi
mkdir -p apps
cd apps
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
  NETWORKS=${NETWORKS},${NETOP_NETWORK_NAME}-${NIDX}
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
HEREDOC1
for DEVDEF in ${NETOP_NETLIST[@]};do
  NIDX=`echo ${DEVDEF}|cut -d',' -f1`
cat << HEREDOC2 >> ./${NAME}.yaml
      requests:
        nvidia.com/${NETOP_RESOURCE}_${NIDX}: '1'
      limits:
        nvidia.com/${NETOP_RESOURCE}_${NIDX}: '1'
HEREDOC2
done
cat << HEREDOC3 >> ./${NAME}.yaml
    command:
    - sh
    - -c
    - sleep inf
HEREDOC3
if [ "${NODE}" != "" ];then
cat << NODEDOC >> ./${NAME}.yaml
  nodeSelector:
    # Note: Replace hostname or remove selector altogether
    kubernetes.io/hostname: ${NODE}
NODEDOC
fi
kubectl apply -f ./${NAME}.yaml
