#!/bin/bash -x
#
# pull and export a release of containers/{VERSION}
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function getTool()
{
  TOOL=$(which crictl)
  if [ "${TOOL}" != "" ];then
    TTYPE="crictl"
  else
    TOOL=$(which docker)
    if [ "${TOOL}" != "" ];then
      TTYPE="docker"
    else
      TOOL=$(which podman)
      if [ "${TOOL}" != "" ];then
        TTYPE="podman"
      else
        TOOL=$(which ctr)
        if [ "${TOOL}" != "" ];then
          TTYPE="ctr"
        else
          echo "no crictl/docker/podman/ctr registry tool"
          exit 1
        fi
      fi
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
    fi
    CONTAINER_PATH="${REPOSITORY}/${CONTAINER}:${RELEASE_TAG}"
    TARBALL=$(echo ${CONTAINER_PATH} | sed 's,/,_,g' | sed 's/:/+/').tgz
    case ${TTYPE} in
    crictl)
      ${TOOL} pull --creds '$oauthtoken':"${NGC_API_KEY}" ${CONTAINER_PATH}
      if [ "$?" != "0" ];then
        echo "CONTAINER PULL FAILED: ${TOOL} pull --creds '$oauthtoken':${NGC_API_KEY} ${CONTAINER_PATH}"
        exit 1
      fi
      ;;
    docker|podman)
      echo "${NGC_API_KEY}" | ${TOOL} login --username  '$oauthtoken' --password-stdin ${REPOSITORY}
      ${TOOL} pull ${CONTAINER_PATH}
      if [ "$?" != "0" ];then
        echo "CONTAINER PULL FAILED: ${TOOL} pull ${CONTAINER_PATH}"
        exit 1
      fi
      if [ ! -f ${TARBALL} ];then
        ${TOOL} save ${CONTAINER_PATH}>${TARBALL}
      fi
      ;;
    ctr)
      ${TOOL} images pull --user '$oauthtoken':"${NGC_API_KEY}" ${CONTAINER_PATH}
      if [ "$?" != "0" ];then
        echo "CONTAINER PULL FAILED: ${TOOL} images pull --user '$oauthtoken':${NGC_API_KEY} ${CONTAINER_PATH}"
        exit 1
      fi
      if [ ! -f ${TARBALL} ];then
        ${TOOL} -n k8s.io images export ${TARBALL} ${CONTAINER_PATH}
      fi
      ;;
    esac
  done <"${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
}
pullContainers
