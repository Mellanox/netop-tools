#!/bin/bash -x
#
# Go to NGC catalog
# Down load
#
# https://catalog.ngc.nvidia.com/orgs/nvidia/teams/cloud-native/helm-charts/network-operator
#
source ./netop.cfg
source ./ops/cordon.sh
cordon
#../install/ins-netop-chart.sh
pushd .
cd ./netop-chart
## if [ ! -d "network-operator" ];then
##  if [ "${PROD_VER}" = "1" ];tehn
##  else
##   helm fetch ${DEV_URL} --username="\$oauthtoken" --password=${NGC_API_KEY}
##   tar -xvf network-operator-${NETOP_VERSION}.tgz
##  fi
## fi
kubectl scale deployment --replicas=0 -n ${NETOP_NAMESPACE} network-operator
popd
#
# should this be commented out
#
#../install/applycrds.sh
#helm upgrade
#
# the yaml file needs to be the custom network operator configuration to overider the defaults
#
cd ./netop-chart
pwd
#helm upgrade -n ${NETOP_NAMESPACE} network-operator network-operator -f ./network-operator-values.yaml
#helm upgrade -n ${NETOP_NAMESPACE} network-operator network-operator -f ../../../values.yaml
helm upgrade -n ${NETOP_NAMESPACE} network-operator nvidia/network-operator -f ../../../values.yaml
uncordon
