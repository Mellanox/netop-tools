#!/bin/bash
#
# pull and export a release of containers/{VERSION}
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
function getTool()
{
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
        TOOL=$(which crictl)
        if [ "${TOOL}" != "" ];then
          TTYPE="crictl"
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
function docker_save_tarball()
{
  if [ ! -f ${TARBALL} ];then
    ${TOOL} save ${CONTAINER_PATH}>${TARBALL}
  fi
}
function ctr_save_tarball
{
  if [ ! -f ${TARBALL} ];then
    ${TOOL} -n k8s.io images export ${TARBALL} ${CONTAINER_PATH}
  fi
}
function requires_ngc_auth()
{
  echo "${1}" | grep -q "nvcr.io/nvstaging"
}
function is_nvcr_repo()
{
  echo "${1}" | grep -q "^nvcr.io/"
}
function has_ngc_api_key()
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
  return ${HAS_KEY}
}
function require_ngc_api_key()
{
  if ! has_ngc_api_key;then
    echo "ERROR: NGC_API_KEY is required for nvstaging pulls"
    exit 1
  fi
}
function should_use_ngc_auth()
{
  is_nvcr_repo "${1}" && has_ngc_api_key
}
function registry_host()
{
  echo "${1}" | cut -d/ -f1
}
function registry_login()
{
  local REPOSITORY="${1}"
  local REGISTRY_HOST
  local XTRACE_WAS_ENABLED=0

  REGISTRY_HOST=$(registry_host "${REPOSITORY}")
  case $- in
  *x*)
    XTRACE_WAS_ENABLED=1
    set +x
    ;;
  esac
  printf '%s\n' "${NGC_API_KEY}" | ${TOOL} login --username '$oauthtoken' --password-stdin "${REGISTRY_HOST}"
  local STATUS=$?
  if [ "${XTRACE_WAS_ENABLED}" = "1" ];then
    set -x
  fi
  return ${STATUS}
}
function run_password_prompted_command()
{
  local CMD=""
  local ARG
  local QUOTED_ARG
  local XTRACE_WAS_ENABLED=0
  local STATUS

  if ! command -v script >/dev/null 2>&1;then
    echo "ERROR: script(1) is required to pass ${TTYPE} registry passwords without argv exposure"
    exit 1
  fi

  for ARG in "$@";do
    printf -v QUOTED_ARG "%q" "${ARG}"
    CMD="${CMD} ${QUOTED_ARG}"
  done
  CMD="${CMD# }"

  case $- in
  *x*)
    XTRACE_WAS_ENABLED=1
    set +x
    ;;
  esac
  printf '%s\n' "${NGC_API_KEY}" | script -q -e -E never -c "${CMD}" /dev/null
  STATUS=$?
  if [ "${XTRACE_WAS_ENABLED}" = "1" ];then
    set -x
  fi
  return ${STATUS}
}
function pullContainers()
{
  getTool
  while read LINE;do
    REPOSITORY=$(echo "${LINE}" | cut -d, -f3)
    CONTAINER=$(echo ${LINE}|cut -d, -f4)
    #CONTAINER=$(docaImage ${CONTAINER})
    RELEASE_TAG=$(echo "${LINE}" | cut -d, -f5)
    MOD_TAG=$(echo "${LINE}" | cut -d, -f6)
    if requires_ngc_auth "${REPOSITORY}";then
      require_ngc_api_key
    fi
    CONTAINER_PATH="${REPOSITORY}/${CONTAINER}:${RELEASE_TAG}${MOD_TAG}"
    TARBALL=$(echo ${CONTAINER_PATH} | sed 's,/,_,g' | sed 's/:/+/').tgz
    case ${TTYPE} in
    crictl)
      if should_use_ngc_auth "${REPOSITORY}";then
        run_password_prompted_command "${TOOL}" pull --username '$oauthtoken' "${CONTAINER_PATH}"
      else
        ${TOOL} pull ${CONTAINER_PATH}
      fi
      if [ "$?" != "0" ];then
        if should_use_ngc_auth "${REPOSITORY}";then
          echo "CONTAINER PULL FAILED: ${TOOL} pull --creds \$oauthtoken:<REDACTED> ${CONTAINER_PATH}"
        else
          echo "CONTAINER PULL FAILED: ${TOOL} pull ${CONTAINER_PATH}"
        fi
        exit 1
      fi
      ;;
    docker|podman)
      if should_use_ngc_auth "${REPOSITORY}";then
        registry_login "${REPOSITORY}" || exit 1
      fi
      ${TOOL} pull ${CONTAINER_PATH}
      if [ "$?" != "0" ];then
        echo "CONTAINER PULL FAILED: ${TOOL} pull ${CONTAINER_PATH}"
        exit 1
      fi
      docker_save_tarball
      ;;
    ctr)
      if should_use_ngc_auth "${REPOSITORY}";then
        run_password_prompted_command "${TOOL}" images pull --user '$oauthtoken' "${CONTAINER_PATH}"
      else
        ${TOOL} images pull ${CONTAINER_PATH}
      fi
      if [ "$?" != "0" ];then
        if should_use_ngc_auth "${REPOSITORY}";then
          echo "CONTAINER PULL FAILED: ${TOOL} images pull --user \$oauthtoken:<REDACTED> ${CONTAINER_PATH}"
        else
          echo "CONTAINER PULL FAILED: ${TOOL} images pull ${CONTAINER_PATH}"
        fi
        exit 1
      fi
      ctr_save_tarball
      ;;
    esac
  done <"${NETOP_ROOT_DIR}/containers/${NETOP_VERSION}"
}
pullContainers
