#!/bin/bash +x
#
# create a secrets file for nvstaging
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
if [ "${PROD_VER}" = "0" ];then
  FILE="/root/.docker/config.json"
  ${NETOP_ROOT_DIR}/uninstall/delsecret.sh
  echo "START"
  docker login --username '$oauthtoken' nvcr.io
  echo "END"
  X=`${K8CL} get secret -n ${NETOP_NAMESPACE} | grep -c "${NGC_SECRET}"`
  if [ "${X}" = "0" ];then
    ${K8CL} -n ${NETOP_NAMESPACE} create secret docker-registry ${NGC_SECRET} --docker-server=nvcr.io --docker-username="\$oauthtoken" --docker-password=${NGC_API_KEY}
    ${K8CL} -n ${NETOP_NAMESPACE} create secret generic ${NGC_SECRET} --from-file=.dockerconfigjson=${FILE} --type=kubernetes.io/dockerconfigjson
  fi
  #${K8CL} -n network-operator create secret generic ngc-image-secret --from-file=.dockerconfigjson=~/.docker/config.json --type=kubernetes.io/dockerconfigjson
fi
