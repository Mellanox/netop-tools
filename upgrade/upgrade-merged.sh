#!/bin/bash
#
# Upgrade network-operator using a merged set of already rendered usecases.
# Shared/operator-scoped artifacts are merged into one output directory, while
# per-usecase network/IPAM manifests are applied from each rendered usecase.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETOP_ROOT_DIR="${NETOP_ROOT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

source "${NETOP_ROOT_DIR}/global_ops.cfg"
source "${NETOP_ROOT_DIR}/ops/cordon.sh"

MERGED_DIR="${NETOP_ROOT_DIR}/usecase/merged"
USECASE_ARGS=()
USECASES=()
CORDONED=false

usage()
{
  cat <<'USAGE'
usage: upgrade/upgrade-merged.sh [--merged-dir DIR] USECASE [USECASE...]

Merges already rendered usecases, applies the merged operator-scoped artifacts,
applies each usecase's rendered CRDs, and upgrades the network-operator Helm
release with the merged values.yaml.

Arguments:
  USECASE        Usecase name under usecase/ or a path under usecase/

Options:
  --merged-dir   Output directory for merged artifacts (default: usecase/merged)
  -h, --help     Show this help text
USAGE
}

cleanup()
{
  if [ "${CORDONED}" = "true" ];then
    uncordon
  fi
}

resolve_usecase()
{
  local INPUT="${1}"
  local CANDIDATE=""
  local REAL=""
  local ROOT_USECASE_DIR="${NETOP_ROOT_DIR}/usecase"

  if [ -d "${ROOT_USECASE_DIR}/${INPUT}" ];then
    echo "${INPUT}"
    return 0
  fi

  if [ -d "${INPUT}" ];then
    REAL="$(realpath "${INPUT}")"
    CANDIDATE="${REAL##*/}"
    if [ "${REAL%/${CANDIDATE}}" != "$(realpath "${ROOT_USECASE_DIR}")" ];then
      echo "ERROR: explicit usecase paths must be under ${ROOT_USECASE_DIR}: ${INPUT}" >&2
      return 1
    fi
    echo "${CANDIDATE}"
    return 0
  fi

  echo "ERROR: usecase not found: ${INPUT}" >&2
  return 1
}

parse_args()
{
  while [ $# -gt 0 ];do
    case "${1}" in
      --merged-dir)
        if [ $# -lt 2 ];then
          echo "ERROR: --merged-dir requires a directory argument" >&2
          exit 1
        fi
        MERGED_DIR="${2}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "ERROR: unknown option: ${1}" >&2
        usage >&2
        exit 1
        ;;
      *)
        USECASE_ARGS+=("${1}")
        shift
        ;;
    esac
  done

  if [ $# -gt 0 ];then
    USECASE_ARGS+=("$@")
  fi

  if [ ${#USECASE_ARGS[@]} -eq 0 ];then
    echo "ERROR: at least one usecase is required" >&2
    usage >&2
    exit 1
  fi

  local RESOLVED=""
  local UC=""
  for UC in "${USECASE_ARGS[@]}";do
    RESOLVED="$(resolve_usecase "${UC}")"
    if [[ " ${USECASES[*]} " != *" ${RESOLVED} "* ]];then
      USECASES+=("${RESOLVED}")
    fi
  done
}

merge_usecases()
{
  "${NETOP_ROOT_DIR}/ops/merge-usecases.py" \
    --root-dir "${NETOP_ROOT_DIR}" \
    --output-dir "${MERGED_DIR}" \
    --values-file "${NETOP_VALUES_FILE}" \
    --niccluster-file "${NETOP_NICCLUSTER_FILE}" \
    "${USECASES[@]}"
}

apply_merged_nic_config_crds()
{
  local CRD=""
  shopt -s nullglob
  for CRD in "${MERGED_DIR}"/nic-config-crd-*.yaml;do
    ${K8CL} apply -f "${CRD}"
  done
  shopt -u nullglob
}

apply_rendered_usecase_crds()
{
  local UC=""
  for UC in "${USECASES[@]}";do
    echo "Applying rendered CRDs for usecase: ${UC}"
    USECASE="${UC}" "${NETOP_ROOT_DIR}/ops/apply-network-cr.sh"
  done
}

main()
{
  parse_args "$@"
  MERGED_DIR="$(realpath -m "${MERGED_DIR}")"

  trap cleanup EXIT

  cordon
  CORDONED=true

  export NETOP_CHART_DIR="${NETOP_ROOT_DIR}/release/${NETOP_VERSION}/netop-chart"
  merge_usecases

  ${K8CL} scale deployment --replicas=0 -n "${NETOP_NAMESPACE}" network-operator

  "${NETOP_ROOT_DIR}/install/applycrds.sh"
  ${K8CL} apply -f "${MERGED_DIR}/${NETOP_NICCLUSTER_FILE}"
  apply_merged_nic_config_crds
  apply_rendered_usecase_crds

  ${HELMCL} upgrade -n "${NETOP_NAMESPACE}" \
    network-operator \
    "${NETOP_CHART_DIR}/network-operator" \
    -f "${MERGED_DIR}/${NETOP_VALUES_FILE}"

  CORDONED=false
  uncordon
  trap - EXIT
}

main "$@"
