#!/bin/bash
#
# pod.yaml configuration file for such a deployment:
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
NAME=${1}
shift
DEV=${1}
shift
NODE=${1}
shift
if [ "${NAME}" = "" ];then
	echo "usage:$0 {podname} {networkid}"
	echo "usage:$0 {podname} {network id} {worker node}"
	exit 1
fi
mkdir -p apps
cd apps
cat << HEREDOC > ./${NAME}.yaml
apiVersion: v1
kind: Pod
metadata:
  name: ${NAME}
  annotations:
    k8s.v1.cni.cncf.io/networks: ${NETOP_NETWORK_NAME}-${DEV}
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
        nvidia.com/${NETOP_RESOURCE}_${DEV}: '1'
      limits:
        nvidia.com/${NETOP_RESOURCE}_${DEV}: '1'
    command:
    - sh
    - -c
    - sleep inf
HEREDOC
if [ "${NODE}" != "" ];then
cat << NODEDOC >> ./${NAME}.yaml
  nodeSelector:
    # Note: Replace hostname or remove selector altogether
    kubernetes.io/hostname: ${NODE}
NODEDOC
fi
kubectl apply -f ./${NAME}.yaml