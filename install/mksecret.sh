#!/bin/bash +x
#
# create a secrets file for nvstaging
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function getTool()
{
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
}
if [ "${PROD_VER}" != "0" ];then
  return
fi
${NETOP_ROOT_DIR}/uninstall/delsecret.sh
#echo "${NGC_API_KEY}" | ${TOOL} login --username  '$oauthtoken' --password-stdin nvcr.io
X=$(${K8CL} get secret -n ${NETOP_NAMESPACE} | grep -c "${NGC_SECRET}")
if [ "${X}" = "0" ];then
  #${K8CL} -n ${NETOP_NAMESPACE} create secret generic ${NGC_SECRET} --from-file=.dockerconfigjson=${FILE} --type=kubernetes.io/dockerconfigjson
  ${K8CL} -n ${NETOP_NAMESPACE} create secret docker-registry ${NGC_SECRET} --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=${NGC_API_KEY}
fi
