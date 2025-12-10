#!/bin/bash
#
# import and retag and a release of containers/{VERSION}
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function get_container()
{
  while read -u 3 LINE;do
    CONTAINER=$(echo ${LINE}|cut -d, -f4)
    if [ "${CONTAINER}" == "${1}" ];then
       echo "${LINE}"
    fi
  done 3< "${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
}
function get_repository()
{
  LINE=$(get_container ${1})
  REPOSITORY=$(echo "${LINE}" | cut -d, -f3)
  if [ "${2}" = "required" ] &&  [ "${REPOSITORY}" = "" ];then
    echo "required repository ${1} not found in container list ${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
    exit 1
  fi
  echo ${REPOSITORY}
}
function get_release_tag()
{
  LINE=$(get_container ${1})
  echo "${LINE}" | cut -d, -f5
}
function  get_sh256()
{
  sudo ctr -n k8s.io images ls | tr -s [:space:] | cut -d' ' -f3
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
function loadContainers()
{
  while read LINE;do
    REPOSITORY=$(echo "${LINE}" | cut -d, -f3)
    REGISTRY=$(echo REPOSITORY|cut -d'/' -f1)
    REPOPATH=$(echo REPOSITORY|cut -d'/' -f2-)
    CONTAINER=$(echo ${LINE}|cut -d, -f4)
    #CONTAINER=$(docaImage ${CONTAINER})
    RELEASE_TAG=$(echo "${LINE}" | cut -d, -f5)
    MOD_TAG=$(echo "${LINE}" | cut -d, -f6)
    CONTAINER_PATH="${REPOSITORY}/${CONTAINER}:${RELEASE_TAG}${MOD_TAG}"
    if [ $(sudo docker images | tr -s [:space:] | cut -d' ' -f1,2 | sed 's/ /:/'| grep -c "${CONTAINER_PATH}") = "0" ];then
      TARBALL=$(echo ${CONTAINER_PATH} | sed 's,/,_,g' | sed 's/:/+/').tgz
      sudo ctr -n=k8s.io image import ${TARBALL}
    else
      echo "found tag:${CONTAINER_PATH}"
    fi
    NEWREPOSITORY=$(get_repository ${CONTAINER})
    NEWREGISTRY=$(echo NEWREPOSITORY|cut -d'/' -f1)
    NEWREPOPATH=$(echo NEWREPOSITORY|cut -d'/' -f2-)
    #sudo ctr -n k8s.io images tag ${CONTAINER_PATH} "${NEWREPO}/${CONTAINER}:${RELEASE_TAG}${MOD_TAG}"
    sudo docker tag "${CONTAINER_PATH}" "${NEWREPO}/${CONTAINER}:${RELEASE_TAG}${MOD_TAG}"
  done < "${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}.nvstaging"
}
loadContainers
