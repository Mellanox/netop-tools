#!/bin/bash +x
#
# create a secrets file for nvstaging
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
if [ "${PROD_VER}" != "0" ];then
  return
fi
${NETOP_ROOT_DIR}/uninstall/delsecret.sh
echo "START"
TOOL=$(which docker)
if [ "${TOOL}" != "" ];then
  FILE="/root/.docker/config.json"
else
  TOOL=$(which podman)
  if [ "${TOOL}" = "" ];then
    echo "no docker/podman registry login tool"
    exit 1
  fi
  FILE="${XDG_RUNTIME_DIR}/containers/auth.json"
fi
echo "${NGC_API_KEY}" | ${TOOL} login --username  '$oauthtoken' --password-stdin nvcr.io
#${TOOL} login --username '$oauthtoken' nvcr.io
echo "END"
X=`${K8CL} get secret -n ${NETOP_NAMESPACE} | grep -c "${NGC_SECRET}"`
if [ "${X}" = "0" ];then
  ${K8CL} -n ${NETOP_NAMESPACE} create secret docker-registry ${NGC_SECRET} --docker-server=nvcr.io --docker-username="\$oauthtoken" --docker-password=${NGC_API_KEY}
  ${K8CL} -n ${NETOP_NAMESPACE} create secret generic ${NGC_SECRET} --from-file=.dockerconfigjson=${FILE} --type=kubernetes.io/dockerconfigjson
fi
#${K8CL} -n network-operator create secret generic ngc-image-secret --from-file=.dockerconfigjson=~/.docker/config.json --type=kubernetes.io/dockerconfigjson
