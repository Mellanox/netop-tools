#!/bin/bash -x
#
# install the network operator.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${NETOP_ROOT_DIR}/setuc.sh
USECASE_DIR="${NETOP_ROOT_DIR}/usecase/${USECASE}"
systemctl restart kubelet
#helm install -n ${NETOP_NAMESPACE} --create-namespace network-operator ./network-operator
X=`kubectl get ns | grep -c "^${NETOP_NAMESPACE} "`
if [ "${X}" = "0" ];then 
  kubectl create ns ${NETOP_NAMESPACE}
fi
${NETOP_ROOT_DIR}/install/mksecret.sh

cd ${USECASE_DIR}
${NETOP_ROOT_DIR}/ops/mk-values.sh
${NETOP_ROOT_DIR}/ops/mk-nic-cluster-policy.sh
${NETOP_ROOT_DIR}/ops/mk-network-cr.sh

helm install -n ${NETOP_NAMESPACE} network-operator nvidia/network-operator --version ${NETOP_VERSION} \
  -f ${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart/network-operator/values.yaml \
  -f ${USECASE_DIR}/values.yaml
${NETOP_ROOT_DIR}/install/applycrds.sh
