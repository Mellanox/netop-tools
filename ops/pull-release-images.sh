#!/bin/bash -x
#
# pull and export a release of containers
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
function docaImage()
{
  if [ "${1}" = "doca-driver" ];then
    echo ${1}
  else
    ARCH=$(uname -i)
    if [ ${ARCH} = "x86_64" ];then
      ARCH="amd64"
    fi
    echo ${1}-$(uname -r)-${ARCH}
  fi
}
function pullContainers()
{
  getTool
  while read LINE;do
    REPOSITORY=$(echo "${LINE}" | cut -d, -f3)
    CONTAINER=$(echo ${LINE}|cut -d, -f4)
    CONTAINER=$(docaImage ${CONTAINER})
    RELEASE_TAG=$(echo "${LINE}" | cut -d, -f5)
    if [ $(echo ${REPOSITORY} | grep -c "nvcr.io/nvstaging" ) != "0" ];then
      if [ "${NGC_API_KEY}" = "" ];then
        echo "NGC_API_KEY:missing:${NGC_API_KEY}"
        exit 1
      fi
      echo "${NGC_API_KEY}" | ${TOOL} login --username  '$oauthtoken' --password-stdin ${REPOSITORY}
    fi
    CONTAINER_PATH="${REPOSITORY}/${CONTAINER}:${RELEASE_TAG}"
    ${TOOL} pull ${CONTAINER_PATH}
    if [ "$?" != "0" ];then
      echo "CONTAINER PULL FAILED: ${TOOL} pull ${CONTAINER_PATH}"
      exit 1
    fi
    TARBALL=$(echo ${CONTAINER_PATH} | sed 's,/,_,g').tgz
    ${TOOL} save ${CONTAINER_PATH}>${TARBALL}
  done <"${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
}
pullContainers
