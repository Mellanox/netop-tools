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
  echo "ERROR: NGC_API_KEY is required for staging Helm chart access"
  exit 1
fi
}

function get_chart()
{
if [ ! -f network-operator-${NETOP_VERSION}.tgz ];then
  if [ "${PROD_VER}" = "0" ];then
    require_ngc_api_key
    "${NETOP_ROOT_DIR}/install/ins-helm-repo.sh" || exit 1
    ${HELMCL} fetch nvidia/network-operator --version "${NETOP_VERSION}" || exit 1
  else
    ${HELMCL} fetch "${NETOP_HELM_URL}" || exit 1
  fi
  tar -xvf network-operator-*.tgz || exit 1
fi
}
NETOP_CHART_DIR=${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart
[ ! -d ${NETOP_CHART_DIR} ] && mkdir -p ${NETOP_CHART_DIR}
cd "${NETOP_CHART_DIR}"
get_chart
