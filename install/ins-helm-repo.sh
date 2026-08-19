#!/bin/bash
#
# install the network operator chart
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

function require_ngc_api_key()
{
local XTRACE_WAS_ENABLED=0
local HAS_KEY
case $- in
*x*)
  XTRACE_WAS_ENABLED=1
  set +x
  ;;
esac
[ -n "${NGC_API_KEY:-}" ]
HAS_KEY=$?
if [ "${XTRACE_WAS_ENABLED}" = "1" ];then
  set -x
fi
if [ ${HAS_KEY} -ne 0 ];then
  echo "ERROR: NGC_API_KEY is required for staging Helm repo access"
  exit 1
fi
}

function add_staging_repo()
{
local XTRACE_WAS_ENABLED=0
case $- in
*x*)
  XTRACE_WAS_ENABLED=1
  set +x
  ;;
esac
printf '%s\n' "${NGC_API_KEY}" | ${HELMCL} repo add nvidia "${HELM_NVIDIA_REPO}" --username='$oauthtoken' --password-stdin
local STATUS=$?
if [ "${XTRACE_WAS_ENABLED}" = "1" ];then
  set -x
fi
return ${STATUS}
}

function get_repo()
{
X=$(${HELMCL} repo list | cut -d' ' -f1 | grep -c nvidia)
if [ ${X} -ne 0 ];then
  ${HELMCL} repo remove nvidia
fi
if [ "${PROD_VER}" = "0" ];then
  echo "STAGING:${PROD_VER}"
  require_ngc_api_key
  add_staging_repo || exit 1
else
  echo "PROD:${PROD_VER}"
  ${HELMCL} repo add nvidia "${HELM_NVIDIA_REPO}"
fi
${HELMCL} repo update
}
get_repo
