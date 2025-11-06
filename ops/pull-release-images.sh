#!/bin/bash -x
#
# pull and export a release of containers
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function getTool()
{
  TOOL=$(which docker)
  if [ "${TOOL}" != "" ];then
    TTYPE="docker"
  else
    TOOL=$(which podman)
    if [ "${TOOL}" = "" ];then
      TOOL=$(which ctr)
      if [ "${TOOL}" = "" ];then
        echo "no docker/podman/ctr registry login tool"
        exit 1
      else
        TTYPE="ctr"
      fi
    else
      TTYPE="podman"
    fi
  fi
}
function docaImage()
{
  if [ "${1}" != "doca-driver" ];then
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
      case ${TTYPE} in
      docker|podman)
        echo "${NGC_API_KEY}" | ${TOOL} login --username  '$oauthtoken' --password-stdin ${REPOSITORY}
        ;;
      esac
    fi
    CONTAINER_PATH="${REPOSITORY}/${CONTAINER}:${RELEASE_TAG}"
    case ${TTYPE} in
    docker|podman)
      ${TOOL} pull ${CONTAINER_PATH}
      ;;
    ctr)
      ${TOOL} images pull --user '$oauthtoken':"${NGC_API_KEY}" ${CONTAINER_PATH}
    esac
    if [ "$?" != "0" ];then
      echo "CONTAINER PULL FAILED: ${TOOL} pull ${CONTAINER_PATH}"
      exit 1
    fi
    TARBALL=$(echo ${CONTAINER_PATH} | sed 's,/,_,g' | sed 's/:/+/').tgz
    if [ ! -f ${TARBALL} ];then
      ${TOOL} save ${CONTAINER_PATH}>${TARBALL}
    fi
  done <"${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
}
pullContainers
