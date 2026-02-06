#!/bin/bash -x
#
# install the network operator from  the local release dir.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
USECASE_DIR="${NETOP_ROOT_DIR}/usecase/${USECASE}"
RELEASE_DIR=${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart
RELEASE_VALUES=${RELEASE_DIR}/network-operator/values.yaml
function config()
{
  ${NETOP_ROOT_DIR}/setuc.sh
  #${docmd} systemctl restart kubelet
  X=`${docmd} ${K8CL} get ns | grep -c "^${NETOP_NAMESPACE} "`
  if [ "${X}" = "0" ];then 
    ${docmd} ${K8CL} create ns ${NETOP_NAMESPACE}
  fi
  ${NETOP_ROOT_DIR}/install/mksecret.sh
  
  cd "${USECASE_DIR}"
  ${NETOP_ROOT_DIR}/ops/mk-config.sh
}
function release()
{
  # if the release values file exists, use it, otherwise use an empty string
  # and install network-operator according to documentation
  [[ -r ${RELEASE_VALUES} ]] && RELEASE_VALUES="-f ${RELEASE_VALUES}" || RELEASE_VALUES=""
  
  pushd .
  cd "${RELEASE_DIR}"
  helm uninstall -n ${NETOP_NAMESPACE} network-operator 
  helm install --debug -n ${NETOP_NAMESPACE} network-operator ./network-operator ${RELEASE_VALUES} \
   -f ${USECASE_DIR}/${NETOP_VALUES_FILE} --wait
  popd
}
function crds()
{
  ${NETOP_ROOT_DIR}/install/applycrds.sh
  ${docmd} ${K8CL} apply -f ${USECASE_DIR}/${NETOP_NICCLUSTER_FILE}
  if [ "${NIC_CONFIG_ENABLE}" = "true" ];then
    for DEVICE_TYPE in ${DEVICE_TYPES[@]};do
      ${docmd} ${K8CL} apply -f ${USECASE_DIR}/nic-config-crd-${DEVICE_TYPE}.yaml
    done
  fi
  ${NETOP_ROOT_DIR}/ops/apply-network-cr.sh
}
config
release
crds
