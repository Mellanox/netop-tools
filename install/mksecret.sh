#!/bin/bash
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
  exit
fi
if [ "${CREATE_CONFIG_ONLY}" = "1" ];then
  echo "Install command: ${K8CL} delete secret ${NGC_SECRET} -n ${NETOP_NAMESPACE}"
  echo "Install command: ${K8CL} -n ${NETOP_NAMESPACE} create secret generic ${NGC_SECRET} --from-file=.dockerconfigjson=<tempfile> --type=kubernetes.io/dockerconfigjson"
  exit
fi
XTRACE_WAS_ENABLED=0
HAS_NGC_API_KEY=0
case $- in
*x*)
  XTRACE_WAS_ENABLED=1
  set +x
  ;;
esac
[ -n "${NGC_API_KEY:-}" ]
HAS_NGC_API_KEY=$?
if [ "${XTRACE_WAS_ENABLED}" = "1" ];then
  set -x
fi
if [ ${HAS_NGC_API_KEY} -ne 0 ];then
  echo "ERROR: NGC_API_KEY is required to create the staging image pull secret"
  exit 1
fi
${NETOP_ROOT_DIR}/uninstall/delsecret.sh
FILE=$(mktemp "${TMPDIR:-/tmp}/netop-dockerconfig.XXXXXX")
trap 'rm -f "${FILE}"' EXIT
chmod 0600 "${FILE}"
XTRACE_WAS_ENABLED=0
case $- in
*x*)
  XTRACE_WAS_ENABLED=1
  set +x
  ;;
esac
AUTH=$(printf '%s' "\$oauthtoken:${NGC_API_KEY}" | base64 -w0)
cat << DOCKER > "${FILE}"
{
  "auths": {
    "nvcr.io": {
      "username": "\$oauthtoken",
      "password": "${NGC_API_KEY}",
      "auth": "${AUTH}"
    }
  }
}
DOCKER
if [ "${XTRACE_WAS_ENABLED}" = "1" ];then
  set -x
fi
X=$(${K8CL} get secret -n ${NETOP_NAMESPACE} | grep -c "${NGC_SECRET}")
if [ "${X}" = "0" ];then
  ${K8CL} -n ${NETOP_NAMESPACE} create secret generic ${NGC_SECRET} --from-file=.dockerconfigjson="${FILE}" --type=kubernetes.io/dockerconfigjson
fi
