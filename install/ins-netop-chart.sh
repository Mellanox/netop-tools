#!/bin/bash
#
# install the network operator chart
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
NETOP_CHART_DIR=${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart

[ ! -d ${NETOP_CHART_DIR} ] && mkdir -p ${NETOP_CHART_DIR}

cd ${NETOP_CHART_DIR}

X=$(helm repo list | cut -d' ' -f1 | grep -c nvidia)
if [ ${X} -ne 0 ];then
  helm repo remove nvidia
fi
if [ ${PROD_VER} -eq 0 ];then
  echo "STAGING:${PROD_VER}"
  helm repo add nvidia ${HELM_NVIDIA_REPO} --username='$oauthtoken' --password=${NGC_API_KEY}
else
  echo "PROD:${PROD_VER}"
  helm repo add nvidia ${HELM_NVIDIA_REPO}
fi
helm repo update
if [ ! -f network-operator-${NETOP_VERSION}.tgz ];then
  if [ "${PROD_VER}" = "0" ];then
    helm fetch ${NETOP_HELM_URL} --username='$oauthtoken' --password=${NGC_API_KEY}
  else
    helm fetch ${NETOP_HELM_URL}
  fi
  tar -xvf network-operator-*.tgz
fi
