#!/bin/bash
#
# Delete stale pool-suffixed SriovNetwork and NetworkAttachmentDefinition objects.
# Defaults to dry-run; pass --apply to delete.
#

set -uo pipefail

function usage()
{
  cat <<EOF
Usage: $0 [--apply] [--network-base NAME] [--pools POOL[,POOL...]]
          [--devices DEV[,DEV...]] [--app-namespaces NS[,NS...]]
          [--netop-namespace NS]

Deletes only old pool-suffixed network names:
  <network-base>-<pool>-<app-namespace>-<device>

Examples:
  $0 --network-base cx8-vf --pools 05,16 --devices a,b,c,d,e,f,g,h
  $0 --network-base cx8-vf --pools 05,16 --devices a,b,c,d,e,f,g,h --apply

Options:
  --apply                  Actually delete matching resources. Default is dry-run.
  --network-base NAME      Base network name. Default: NETOP_NETWORK_NAME.
  --pools LIST             Pool IDs or NETOP_NETLIST_* variable names.
                            Default: NETOP_NODEPOOLS or NETOP_NODE_POOLS.
  --devices LIST           Device indexes. Default: first field from pool NETOP_NETLIST arrays.
  --app-namespaces LIST    App namespaces containing NADs. Default: NETOP_APP_NAMESPACES.
  --netop-namespace NS     Namespace containing SriovNetwork. Default: NETOP_NAMESPACE.
  -h, --help               Show this help.
EOF
}

if [ -z "${NETOP_ROOT_DIR:-}" ]; then
  NETOP_ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  export NETOP_ROOT_DIR
fi

if [[ "${NETOP_ROOT_DIR}" != *[[:space:]]* ]] && [ -r "${NETOP_ROOT_DIR}/global_ops.cfg" ]; then
  user_cfg="${GLOBAL_OPS_USER:-${NETOP_ROOT_DIR}/global_ops_user.cfg}"
  if [ -r "${user_cfg}" ]; then
    # shellcheck source=/dev/null
    source "${NETOP_ROOT_DIR}/global_ops.cfg"
  fi
fi

K8CL=${K8CL:-kubectl}
APPLY=false
NETWORK_BASE=${NETWORK_BASE:-${NETOP_NETWORK_NAME:-}}
NETOP_NS=${NETOP_NS:-${NETOP_NAMESPACE:-nvidia-network-operator}}
CLI_POOLS=()
CLI_DEVICES=()
CLI_APP_NAMESPACES=()

read -r -a K8CL_CMD <<< "${K8CL}"

function append_csv()
{
  local -n out=$1
  local input=${2// /}
  local item
  local -a values

  IFS=',' read -r -a values <<< "${input}"
  for item in "${values[@]}"; do
    [ -n "${item}" ] || continue
    out+=("${item}")
  done
}

while [ $# -gt 0 ]; do
  case "${1}" in
  --apply)
    APPLY=true
    shift
    ;;
  --network-base)
    NETWORK_BASE=${2:-}
    shift 2
    ;;
  --pools)
    append_csv CLI_POOLS "${2:-}"
    shift 2
    ;;
  --devices)
    append_csv CLI_DEVICES "${2:-}"
    shift 2
    ;;
  --app-namespaces)
    append_csv CLI_APP_NAMESPACES "${2:-}"
    shift 2
    ;;
  --netop-namespace)
    NETOP_NS=${2:-}
    shift 2
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  -*)
    echo "ERROR: unknown option ${1}" >&2
    usage >&2
    exit 2
    ;;
  *)
    echo "ERROR: unexpected argument ${1}" >&2
    usage >&2
    exit 2
    ;;
  esac
done

function kctl()
{
  "${K8CL_CMD[@]}" "$@"
}

function pool_id()
{
  local raw=${1}

  raw=${raw#NETOP_NETLIST}
  raw=${raw#_}
  echo "${raw,,}"
}

function add_unique()
{
  local -n out=$1
  local value=${2}
  local existing

  [ -n "${value}" ] || return
  for existing in "${out[@]}"; do
    [ "${existing}" = "${value}" ] && return
  done
  out+=("${value}")
}

function add_devices_from_netlist_var()
{
  local var=${1}
  local devdef
  local dev
  local -a entries

  declare -p "${var}" >/dev/null 2>&1 || return
  eval "entries=( \"\${${var}[@]}\" )"
  for devdef in "${entries[@]}"; do
    dev=${devdef%%,*}
    add_unique DEVICES "${dev}"
  done
}

function resolve_pool_sources()
{
  POOL_SOURCES=()
  local item

  if [ ${#CLI_POOLS[@]} -gt 0 ]; then
    for item in "${CLI_POOLS[@]}"; do
      POOL_SOURCES+=("${item}")
    done
    return
  fi

  if declare -p NETOP_NODEPOOLS >/dev/null 2>&1; then
    case "$(declare -p NETOP_NODEPOOLS)" in
    declare\ -a*)
      eval 'POOL_SOURCES=( "${NETOP_NODEPOOLS[@]}" )'
      ;;
    *)
      append_csv POOL_SOURCES "${NETOP_NODEPOOLS}"
      ;;
    esac
  fi

  if [ ${#POOL_SOURCES[@]} -eq 0 ] && declare -p NETOP_NODE_POOLS >/dev/null 2>&1; then
    case "$(declare -p NETOP_NODE_POOLS)" in
    declare\ -a*)
      eval 'POOL_SOURCES=( "${NETOP_NODE_POOLS[@]}" )'
      ;;
    *)
      append_csv POOL_SOURCES "${NETOP_NODE_POOLS}"
      ;;
    esac
  fi
}

function resolve_devices()
{
  DEVICES=()
  local item
  local pid
  local var

  if [ ${#CLI_DEVICES[@]} -gt 0 ]; then
    for item in "${CLI_DEVICES[@]}"; do
      add_unique DEVICES "${item}"
    done
    return
  fi

  for item in "${POOL_SOURCES[@]}"; do
    if [[ "${item}" == NETOP_NETLIST* ]]; then
      add_devices_from_netlist_var "${item}"
    else
      pid=$(pool_id "${item}")
      var="NETOP_NETLIST_${pid^^}"
      add_devices_from_netlist_var "${var}"
    fi
  done

  add_devices_from_netlist_var NETOP_NETLIST

  if [ ${#DEVICES[@]} -eq 0 ]; then
    echo "WARN: no device indexes found in config; falling back to a-h candidates" >&2
    DEVICES=(a b c d e f g h)
  fi
}

function resolve_app_namespaces()
{
  APP_NAMESPACES=()
  local ns

  if [ ${#CLI_APP_NAMESPACES[@]} -gt 0 ]; then
    for ns in "${CLI_APP_NAMESPACES[@]}"; do
      add_unique APP_NAMESPACES "${ns}"
    done
    return
  fi

  if declare -p NETOP_APP_NAMESPACES >/dev/null 2>&1; then
    eval 'APP_NAMESPACES=( "${NETOP_APP_NAMESPACES[@]}" )'
  fi

  if [ ${#APP_NAMESPACES[@]} -eq 0 ]; then
    APP_NAMESPACES=(default)
  fi
}

function resolve_su_values()
{
  SU_VALUES=()

  if declare -p NETOP_SULIST >/dev/null 2>&1; then
    eval 'SU_VALUES=( "${NETOP_SULIST[@]}" )'
  fi

  if [ ${#SU_VALUES[@]} -eq 0 ]; then
    SU_VALUES=("")
  fi
}

function resource_exists()
{
  local ns=${1}
  local type=${2}
  local name=${3}

  kctl -n "${ns}" get "${type}" "${name}" >/dev/null 2>&1
}

function delete_resource()
{
  local ns=${1}
  local type=${2}
  local name=${3}

  if [ "${APPLY}" = "true" ]; then
    echo "DELETE ${type} ${ns}/${name}"
    kctl -n "${ns}" delete "${type}" "${name}" --ignore-not-found
  else
    echo "DRY-RUN would delete ${type} ${ns}/${name}"
  fi
}

resolve_pool_sources
resolve_devices
resolve_app_namespaces
resolve_su_values

if [ -z "${NETWORK_BASE}" ]; then
  echo "ERROR: network base is unknown. Set NETOP_NETWORK_NAME or pass --network-base." >&2
  exit 2
fi

if [ ${#POOL_SOURCES[@]} -eq 0 ]; then
  echo "ERROR: no node pools found. Set NETOP_NODEPOOLS or pass --pools." >&2
  exit 2
fi

echo "Mode: $([ "${APPLY}" = "true" ] && echo apply || echo dry-run)"
echo "Network base: ${NETWORK_BASE}"
echo "Network Operator namespace: ${NETOP_NS}"
echo "Pools: ${POOL_SOURCES[*]}"
echo "App namespaces: ${APP_NAMESPACES[*]}"
echo "Device indexes: ${DEVICES[*]}"
echo

FOUND=0
CHECKED=0
for pool_source in "${POOL_SOURCES[@]}"; do
  pool=$(pool_id "${pool_source}")
  if [ -z "${pool}" ]; then
    echo "Skipping ${pool_source}: no pool suffix to clean up."
    continue
  fi
  base=${NETWORK_BASE}
  if [[ "${base}" == *"-${pool}" ]]; then
    base=${base%"-${pool}"}
  fi
  for ns in "${APP_NAMESPACES[@]}"; do
    for dev in "${DEVICES[@]}"; do
      for su in "${SU_VALUES[@]}"; do
        sutag=${su:+-${su}}
        name="${base}-${pool}-${ns}-${dev}${sutag}"
        CHECKED=$((CHECKED + 1))

        if resource_exists "${NETOP_NS}" sriovnetwork "${name}"; then
          FOUND=$((FOUND + 1))
          delete_resource "${NETOP_NS}" sriovnetwork "${name}"
        fi

        if resource_exists "${ns}" network-attachment-definition "${name}"; then
          FOUND=$((FOUND + 1))
          delete_resource "${ns}" network-attachment-definition "${name}"
        fi
      done
    done
  done
done

echo
echo "Checked ${CHECKED} stale name candidates."
echo "Matched ${FOUND} existing stale resources."
if [ "${APPLY}" != "true" ]; then
  echo "No resources were deleted. Re-run with --apply to delete the matched resources."
fi
