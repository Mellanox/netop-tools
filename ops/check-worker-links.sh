#!/bin/bash
#
# Check physical NVIDIA/Mellanox CX8 and BF3 link state on a worker node.
#
# Discovery intentionally starts from:
#   lspci | grep Mel | grep -v Virt
# and then filters to physical network-link devices matching CX8/ConnectX-8 or
# BF3/BlueField-3. Each matching PCI BDF is checked with:
#   mlxlink -d <PCIeBDF>
#

set -uo pipefail

INCLUDE_REGEX=${LINK_INCLUDE_REGEX:-"CX8|ConnectX-8|BlueField-3|BF3"}
EXPECTED_SPEED=${EXPECTED_SPEED:-}
DETAILS=false
ALL_MELLANOX=false
USE_DOMAIN=true
USE_SUDO=true
LOCAL_ONLY=false
SSH_USER=${SSH_USER:-}
SSH_PORT=${SSH_PORT:-}
SSH_IDENTITY_FILE=${SSH_IDENTITY_FILE:-}
SSH_OPTS=${SSH_OPTS:-}
SERVER_TARGETS=()

function usage()
{
  cat <<EOF
Usage: $0 [options] [server-ip-or-host ...]

Checks worker-node physical NVIDIA/Mellanox CX8 and BF3 links using lspci and
mlxlink, then prints a summary report with link state, speed, and detected
problems. With server arguments, SSH is used to run the same check remotely on
each worker; the script does not need to be installed on the remote worker.

Options:
  --expected-speed SPEED  Flag links that do not report SPEED, for example 400G.
                          Can also be set with EXPECTED_SPEED.
  --include-regex REGEX   Device description regex. Default:
                          CX8|ConnectX-8|BlueField-3|BF3
  --all-mellanox          Check all non-virtual Mellanox/NVIDIA network devices,
                          not only CX8/BF3 matches.
  --details               Print raw mlxlink output after the summary.
  --no-domain             Use lspci without -D. Default prefers lspci -D.
  --no-sudo               Do not run mlxlink through sudo when not root.
  --ssh-user USER         SSH username for server args that do not include user@.
                          Can also be set with SSH_USER.
  --ssh-port PORT         SSH port. Can also be set with SSH_PORT.
  --identity-file FILE    SSH private key. Can also be set with SSH_IDENTITY_FILE.
  --ssh-option OPT        Extra SSH option. May be repeated. Example:
                          --ssh-option StrictHostKeyChecking=no
  -h, --help              Show this help.

Examples:
  $0                                  # check local worker
  $0 10.185.179.17 10.185.180.17      # check remote workers
  $0 --ssh-user root --expected-speed 400G 10.185.179.17
  LINK_INCLUDE_REGEX='CX8|BlueField-3' $0 --details
EOF
}

REMOTE_ARGS=()
EXTRA_SSH_OPTIONS=()

while [ $# -gt 0 ]; do
  case "${1}" in
  --expected-speed)
    EXPECTED_SPEED=${2:-}
    REMOTE_ARGS+=( --expected-speed "${EXPECTED_SPEED}" )
    shift 2
    ;;
  --include-regex)
    INCLUDE_REGEX=${2:-}
    REMOTE_ARGS+=( --include-regex "${INCLUDE_REGEX}" )
    shift 2
    ;;
  --all-mellanox)
    ALL_MELLANOX=true
    REMOTE_ARGS+=( --all-mellanox )
    shift
    ;;
  --details)
    DETAILS=true
    REMOTE_ARGS+=( --details )
    shift
    ;;
  --no-domain)
    USE_DOMAIN=false
    REMOTE_ARGS+=( --no-domain )
    shift
    ;;
  --no-sudo)
    USE_SUDO=false
    REMOTE_ARGS+=( --no-sudo )
    shift
    ;;
  --ssh-user)
    SSH_USER=${2:-}
    shift 2
    ;;
  --ssh-port)
    SSH_PORT=${2:-}
    shift 2
    ;;
  --identity-file)
    SSH_IDENTITY_FILE=${2:-}
    shift 2
    ;;
  --ssh-option)
    EXTRA_SSH_OPTIONS+=( "${2:-}" )
    shift 2
    ;;
  --local-only)
    LOCAL_ONLY=true
    shift
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
    SERVER_TARGETS+=( "${1}" )
    shift
    ;;
  esac
done

function expand_local_path()
{
  local path=${1}
  case "${path}" in
    "~/"*) printf '%s\n' "${HOME}/${path#~/}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

function build_ssh_cmd()
{
  SSH_CMD=(ssh)
  if [ -n "${SSH_OPTS}" ]; then
    # shellcheck disable=SC2206
    SSH_CMD+=( ${SSH_OPTS} )
  fi
  if [ ${#EXTRA_SSH_OPTIONS[@]} -gt 0 ]; then
    local opt
    for opt in "${EXTRA_SSH_OPTIONS[@]}"; do
      SSH_CMD+=( -o "${opt}" )
    done
  fi
  if [ -n "${SSH_PORT}" ]; then
    SSH_CMD+=( -p "${SSH_PORT}" )
  fi
  if [ -n "${SSH_IDENTITY_FILE}" ]; then
    SSH_CMD+=( -i "$(expand_local_path "${SSH_IDENTITY_FILE}")" )
  fi
}

function ssh_target()
{
  local target=${1}
  if [ -n "${SSH_USER}" ] && [[ "${target}" != *@* ]]; then
    printf '%s@%s\n' "${SSH_USER}" "${target}"
  else
    printf '%s\n' "${target}"
  fi
}

if [ "${LOCAL_ONLY}" != "true" ] && [ ${#SERVER_TARGETS[@]} -gt 0 ]; then
  build_ssh_cmd
  overall_rc=0
  for server in "${SERVER_TARGETS[@]}"; do
    target=$(ssh_target "${server}")
    echo "================================================================================"
    echo "Remote worker link check: ${target}"
    echo "================================================================================"
    "${SSH_CMD[@]}" "${target}" "bash -s -- --local-only ${REMOTE_ARGS[*]@Q}" < "$0"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      overall_rc=${rc}
      echo "ERROR: remote check failed for ${target} rc=${rc}" >&2
    fi
    echo
  done
  exit "${overall_rc}"
fi

function command_exists()
{
  command -v "${1}" >/dev/null 2>&1
}

function trim()
{
  local value=${1:-}
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

function normalize_bdf()
{
  local bdf=${1}
  if [[ "${bdf}" =~ ^[0-9a-fA-F]{4}: ]]; then
    printf '%s\n' "${bdf}"
  else
    printf '0000:%s\n' "${bdf}"
  fi
}

function lspci_base()
{
  if [ "${USE_DOMAIN}" = "true" ] && lspci -D >/dev/null 2>&1; then
    lspci -D | grep -i "Mel" | grep -vi "Virt" || true
  else
    lspci | grep -i "Mel" | grep -vi "Virt" || true
  fi
}

function is_network_link_device()
{
  local line=${1}
  echo "${line}" | grep -Eiq 'Ethernet controller|Infiniband controller|Network controller'
}

function is_included_device()
{
  local line=${1}

  if [ "${ALL_MELLANOX}" = "true" ]; then
    return 0
  fi
  echo "${line}" | grep -Eiq "${INCLUDE_REGEX}"
}

function sysfs_csv()
{
  local bdf=${1}
  local subdir=${2}
  local path
  local name
  local values=()

  for path in "/sys/bus/pci/devices/${bdf}/${subdir}"/*; do
    [ -e "${path}" ] || continue
    name=$(basename "${path}")
    values+=( "${name}" )
  done
  if [ ${#values[@]} -eq 0 ]; then
    printf -- '-'
  else
    local IFS=,
    printf '%s' "${values[*]}"
  fi
}

function mlx_field()
{
  local key=${1}
  local file=${2}

  awk -F: -v wanted="${key}" '
    BEGIN { wanted=tolower(wanted) }
    {
      lhs=tolower($1)
      gsub(/^[ \t]+|[ \t]+$/, "", lhs)
      if (lhs == wanted) {
        $1=""
        sub(/^:/, "", $0)
        gsub(/^[ \t]+|[ \t]+$/, "", $0)
        print $0
        exit
      }
    }
  ' "${file}"
}

function append_problem()
{
  local -n out=$1
  local problem=${2}

  [ -n "${problem}" ] || return
  out+=( "${problem}" )
}

function join_problems()
{
  local -n values=$1
  local IFS='; '

  if [ ${#values[@]} -eq 0 ]; then
    printf -- '-'
  else
    printf '%s' "${values[*]}"
  fi
}

function short_desc()
{
  local value=${1}
  if [ ${#value} -gt 44 ]; then
    printf '%s...' "${value:0:41}"
  else
    printf '%s' "${value}"
  fi
}

function build_mlxlink_cmd()
{
  MLXLINK_CMD=(mlxlink)
  if [ "${USE_SUDO}" = "true" ] && [ "${EUID}" -ne 0 ] && command_exists sudo; then
    MLXLINK_CMD=(sudo mlxlink)
  fi
}

if ! command_exists lspci; then
  echo "ERROR: lspci not found" >&2
  exit 127
fi
if ! command_exists mlxlink; then
  echo "ERROR: mlxlink not found" >&2
  exit 127
fi

build_mlxlink_cmd

WORKDIR=$(mktemp -d /tmp/netop-worker-links.XXXXXX)
trap 'rm -rf "${WORKDIR}"' EXIT

LSPCI_FILE="${WORKDIR}/lspci.txt"
lspci_base > "${LSPCI_FILE}"

HOSTNAME=$(hostname 2>/dev/null || echo unknown)
TIMESTAMP=$(date -Is)
ROWS=()
PROBLEM_LINES=()
DETAIL_FILES=()

while IFS= read -r line; do
  [ -n "${line}" ] || continue
  is_network_link_device "${line}" || continue
  is_included_device "${line}" || continue

  bdf_raw=${line%% *}
  bdf=$(normalize_bdf "${bdf_raw}")
  desc=${line#* }
  netdevs=$(sysfs_csv "${bdf}" net)
  rdma_devs=$(sysfs_csv "${bdf}" infiniband)
  mlx_out="${WORKDIR}/mlxlink-${bdf//[:.]/_}.txt"
  rc=0

  "${MLXLINK_CMD[@]}" -d "${bdf}" > "${mlx_out}" 2>&1 || rc=$?
  DETAIL_FILES+=( "${mlx_out}" )

  state=$(trim "$(mlx_field "State" "${mlx_out}")")
  physical=$(trim "$(mlx_field "Physical state" "${mlx_out}")")
  speed=$(trim "$(mlx_field "Speed" "${mlx_out}")")
  width=$(trim "$(mlx_field "Width" "${mlx_out}")")
  autoneg=$(trim "$(mlx_field "Auto Negotiation" "${mlx_out}")")
  fec=$(trim "$(mlx_field "FEC" "${mlx_out}")")

  [ -n "${state}" ] || state="-"
  [ -n "${physical}" ] || physical="-"
  [ -n "${speed}" ] || speed="-"
  [ -n "${width}" ] || width="-"
  [ -n "${autoneg}" ] || autoneg="-"
  [ -n "${fec}" ] || fec="-"

  problems=()
  if [ "${rc}" -ne 0 ]; then
    append_problem problems "mlxlink failed rc=${rc}"
  fi
  if [ "${state}" = "-" ]; then
    append_problem problems "missing State"
  elif ! echo "${state}" | grep -Eiq 'active|up'; then
    append_problem problems "state=${state}"
  fi
  if [ "${physical}" = "-" ]; then
    append_problem problems "missing Physical state"
  elif ! echo "${physical}" | grep -Eiq 'linkup|up'; then
    append_problem problems "physical=${physical}"
  fi
  if [ "${speed}" = "-" ] || echo "${speed}" | grep -Eiq 'n/a|unknown|0'; then
    append_problem problems "speed=${speed}"
  fi
  if [ -n "${EXPECTED_SPEED}" ] && [ "${speed}" != "${EXPECTED_SPEED}" ]; then
    append_problem problems "expected speed ${EXPECTED_SPEED}, got ${speed}"
  fi
  if grep -Eiq 'error|failed|failure|bad|unsupported|no signal|cable.*unplug|module.*bad' "${mlx_out}"; then
    append_problem problems "mlxlink output contains error/warning text"
  fi

  if [ ${#problems[@]} -eq 0 ]; then
    status="OK"
  elif [ "${rc}" -ne 0 ]; then
    status="ERROR"
  else
    status="WARN"
  fi

  problem_text=$(join_problems problems)
  if [ "${problem_text}" != "-" ]; then
    PROBLEM_LINES+=( "${bdf}: ${problem_text}" )
  fi

  ROWS+=( "${status}|${bdf}|${netdevs}|${rdma_devs}|${state}|${physical}|${speed}|${width}|${autoneg}|${fec}|$(short_desc "${desc}")|${problem_text}" )
done < "${LSPCI_FILE}"

echo "Worker Mellanox physical link report"
echo "host: ${HOSTNAME}"
echo "time: ${TIMESTAMP}"
echo "discovery: lspci $([ "${USE_DOMAIN}" = "true" ] && echo "-D " || true)| grep -i Mel | grep -vi Virt"
echo "device filter: $([ "${ALL_MELLANOX}" = "true" ] && echo "all non-virtual Mellanox/NVIDIA network devices" || echo "${INCLUDE_REGEX}")"
if [ -n "${EXPECTED_SPEED}" ]; then
  echo "expected speed: ${EXPECTED_SPEED}"
fi
echo

if [ ${#ROWS[@]} -eq 0 ]; then
  echo "SUMMARY: ERROR no matching physical CX8/BF3 Mellanox network links found"
  echo
  echo "Physical Mellanox devices discovered before CX8/BF3 filtering:"
  if [ -s "${LSPCI_FILE}" ]; then
    sed 's/^/  /' "${LSPCI_FILE}"
  else
    echo "  none"
  fi
  exit 1
fi

printf '%-6s %-14s %-18s %-12s %-10s %-14s %-8s %-6s %-8s %-12s %-44s %s\n' \
  "STATUS" "BDF" "NETDEV" "RDMA" "STATE" "PHYSICAL" "SPEED" "WIDTH" "AUTONEG" "FEC" "DEVICE" "PROBLEMS"
printf '%-6s %-14s %-18s %-12s %-10s %-14s %-8s %-6s %-8s %-12s %-44s %s\n' \
  "------" "---" "------" "----" "-----" "--------" "-----" "-----" "-------" "---" "------" "--------"

for row in "${ROWS[@]}"; do
  IFS='|' read -r status bdf netdevs rdma_devs state physical speed width autoneg fec desc problem_text <<< "${row}"
  printf '%-6s %-14s %-18s %-12s %-10s %-14s %-8s %-6s %-8s %-12s %-44s %s\n' \
    "${status}" "${bdf}" "${netdevs}" "${rdma_devs}" "${state}" "${physical}" "${speed}" "${width}" "${autoneg}" "${fec}" "${desc}" "${problem_text}"
done

echo
ok_count=0
warn_count=0
error_count=0
for row in "${ROWS[@]}"; do
  status=${row%%|*}
  case "${status}" in
  OK) ok_count=$((ok_count + 1)) ;;
  WARN) warn_count=$((warn_count + 1)) ;;
  ERROR) error_count=$((error_count + 1)) ;;
  esac
done
echo "SUMMARY: total=${#ROWS[@]} ok=${ok_count} warn=${warn_count} error=${error_count}"

echo
echo "DETECTED PROBLEMS:"
if [ ${#PROBLEM_LINES[@]} -eq 0 ]; then
  echo "  none"
else
  for problem in "${PROBLEM_LINES[@]}"; do
    echo "  - ${problem}"
  done
fi

if [ "${DETAILS}" = "true" ]; then
  echo
  echo "RAW MLXLINK OUTPUT:"
  for file in "${DETAIL_FILES[@]}"; do
    echo
    echo "### ${file##*/}"
    sed 's/^/  /' "${file}"
  done
fi

if [ "${error_count}" -gt 0 ]; then
  exit 2
fi
if [ "${warn_count}" -gt 0 ]; then
  exit 1
fi
