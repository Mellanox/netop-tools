#!/bin/bash
#
# install the network operator chart
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function get_repo()
{
X=$(${HELMCL} repo list | cut -d' ' -f1 | grep -c nvidia)
if [ ${X} -ne 0 ];then
  ${HELMCL} repo remove nvidia
fi
if [ ${PROD_VER} -eq 0 ];then
  echo "STAGING:${PROD_VER}"
  ${HELMCL} repo add nvidia ${HELM_NVIDIA_REPO} --username='$oauthtoken' --password=${NGC_API_KEY}
else
  echo "PROD:${PROD_VER}"
  ${HELMCL} repo add nvidia ${HELM_NVIDIA_REPO}
fi
${HELMCL} repo update
}
get_repo
