#!/bin/bash
#
# install the network operator chart
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function get_chart()
{
if [ ! -f network-operator-${NETOP_VERSION}.tgz ];then
  if [ "${PROD_VER}" = "0" ];then
    helm fetch ${NETOP_HELM_URL} --username='$oauthtoken' --password=${NGC_API_KEY}
  else
    helm fetch ${NETOP_HELM_URL}
  fi
  tar -xvf network-operator-*.tgz
fi
}
NETOP_CHART_DIR=${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart
[ ! -d ${NETOP_CHART_DIR} ] && mkdir -p ${NETOP_CHART_DIR}
cd ${NETOP_CHART_DIR}
get_chart
