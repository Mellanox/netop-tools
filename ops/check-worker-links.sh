#!/bin/bash
#
# Check physical NVIDIA/Mellanox CX8 and BlueField-3 ConnectX-7 link state on a worker node.
#
# Discovery intentionally starts from:
#   lspci | grep Mel | grep -v Virt
# and then filters to physical network-link devices matching CX8/ConnectX-8,
# BlueField-3/BF3, or ConnectX-7/CX7. Each matching PCI BDF is checked with:
#   mlxlink -d <PCIeBDF>
#

set -uo pipefail

INCLUDE_REGEX=${LINK_INCLUDE_REGEX:-"CX8|ConnectX-8|BlueField-3|BF3|ConnectX-7|CX7"}
EXPECTED_SPEED=${EXPECTED_SPEED:-}
DETAILS=false
SUMMARY_ONLY=false
ALL_MELLANOX=false
USE_DOMAIN=true
USE_SUDO=true
COLOR_MODE=${COLOR_MODE:-auto}
REPORT_DIR=${REPORT_DIR:-}
REPORT_FILE=${REPORT_FILE:-}
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

Checks worker-node physical NVIDIA/Mellanox CX8 and BlueField-3 ConnectX-7
links using lspci and mlxlink, then prints a summary report with link state,
speed, and detected problems. With server arguments, SSH is used to run the same
check remotely on each worker; the script does not need to be installed on the
remote worker.

Options:
  --expected-speed SPEED  Flag links that do not report SPEED, for example 400G.
                          Can also be set with EXPECTED_SPEED.
  --include-regex REGEX   Device description regex. Default:
                          CX8|ConnectX-8|BlueField-3|BF3|ConnectX-7|CX7
  --all-mellanox          Check all non-virtual Mellanox/NVIDIA network devices,
                          not only CX8/BF3/CX7 matches.
  --details               Print raw mlxlink output after the summary.
  --summary               Print only summary counts and detected ERROR entries;
                          suppress warnings, per-link table, and raw details.
  --color MODE            Color mode: auto, always, or never. Default: auto.
  --report-dir DIR        Write a timestamped plain-text report in DIR.
                          Can also be set with REPORT_DIR.
  --report-file FILE      Write a plain-text report to FILE.
                          Can also be set with REPORT_FILE.
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
  $0 --report-dir ~/netop-tools/dynamo worker1 worker2
  LINK_INCLUDE_REGEX='CX8|BlueField-3|ConnectX-7' $0 --details
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
  --summary)
    SUMMARY_ONLY=true
    REMOTE_ARGS+=( --summary )
    shift
    ;;
  --color)
    COLOR_MODE=${2:-}
    shift 2
    ;;
  --report-dir|--output-dir)
    REPORT_DIR=${2:-}
    shift 2
    ;;
  --report-file)
    REPORT_FILE=${2:-}
    shift 2
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

case "${COLOR_MODE}" in
auto|always|never|"") ;;
*)
  echo "ERROR: invalid --color mode: ${COLOR_MODE}. Use auto, always, or never." >&2
  exit 2
  ;;
esac

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

REPORT_STARTED=false
function setup_report()
{
  local report_parent

  [ "${REPORT_STARTED}" = "false" ] || return
  if [ -z "${REPORT_DIR}" ] && [ -z "${REPORT_FILE}" ]; then
    return
  fi

  if [ -n "${REPORT_FILE}" ]; then
    REPORT_FILE=$(expand_local_path "${REPORT_FILE}")
    report_parent=$(dirname "${REPORT_FILE}")
    mkdir -p "${report_parent}"
  else
    REPORT_DIR=$(expand_local_path "${REPORT_DIR}")
    mkdir -p "${REPORT_DIR}"
    REPORT_FILE="${REPORT_DIR%/}/netop-worker-links-$(date +%Y%m%d_%H%M%S).txt"
  fi

  REPORT_STARTED=true
  exec > >(tee >(sed -r $'s/\x1B\\[[0-9;]*[A-Za-z]//g' > "${REPORT_FILE}")) 2>&1
  echo "Writing report: ${REPORT_FILE}"
}

setup_report

if [ "${LOCAL_ONLY}" != "true" ] && [ ${#SERVER_TARGETS[@]} -gt 0 ]; then
  build_ssh_cmd
  if [ "${COLOR_MODE}" = "auto" ] && [ -t 1 ]; then
    REMOTE_ARGS+=( --color always )
  elif [ "${COLOR_MODE}" != "auto" ]; then
    REMOTE_ARGS+=( --color "${COLOR_MODE}" )
  fi
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

function color_enabled()
{
  if [ -n "${NO_COLOR:-}" ]; then
    return 1
  fi
  case "${COLOR_MODE}" in
  always) return 0 ;;
  never) return 1 ;;
  auto|"") [ -t 1 ] ;;
  *)
    echo "ERROR: invalid --color mode: ${COLOR_MODE}. Use auto, always, or never." >&2
    exit 2
    ;;
  esac
}

if color_enabled; then
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  RESET=$'\033[0m'
else
  RED=""
  YELLOW=""
  RESET=""
fi

function print_problem_message()
{
  local lead=${1}
  local color=${2}
  local message=${3}
  local prefix=""
  local detail=${message}

  if [[ "${message}" == *": "* ]]; then
    prefix="${message%%: *}: "
    detail="${message#*: }"
  fi

  printf '%s%s%s%s%s\n' "${lead}" "${prefix}" "${color}" "${detail}" "${RESET}"
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

function append_fatal_problem()
{
  local -n problems_ref=$1
  local -n fatal_ref=$2
  local problem=${3}

  append_problem problems_ref "${problem}"
  fatal_ref=true
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

function append_report_problem()
{
  local severity=${1}
  local message=${2}

  PROBLEM_LINES+=( "${severity}|${message}" )
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

function device_family()
{
  local value=${1:-}

  if echo "${value}" | grep -Eiq 'BlueField-3|BF3|MT43244'; then
    printf 'BF3'
  elif echo "${value}" | grep -Eiq 'CX8|ConnectX-8'; then
    printf 'CX8'
  elif echo "${value}" | grep -Eiq 'CX7|ConnectX-7'; then
    printf 'CX7'
  else
    printf 'Mellanox'
  fi
}

function speed_is_invalid()
{
  local value

  value=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  value=${value//[[:space:]]/}
  case "${value}" in
  ""|-|n/a|na|none|unknown|0|0g|0gb/s|0gbps|0mb/s|0mbps|0m)
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

function friendly_physical_state()
{
  local value=${1:-}
  local state_value=${2:-}

  if echo "${state_value}" | grep -Eiq 'signal detect'; then
    printf 'NoSignal'
    return
  fi
  case "${value}" in
  ETH_AN_FSM_ENABLE)
    printf 'LinkTraining'
    ;;
  *)
    printf '%s' "${value}"
    ;;
  esac
}

function summary_condition()
{
  local state_value=${1:-}
  local physical_value=${2:-}
  local speed_value=${3:-}
  local fault_value=${4:-}

  if echo "${fault_value}" | grep -Eiq 'signal not detected' ||
     echo "${state_value}" | grep -Eiq 'signal detect' ||
     echo "${physical_value}" | grep -Eiq '^NoSignal$'; then
    printf 'Down,NoSignal'
  elif echo "${fault_value}" | grep -Eiq 'cable is unplugged'; then
    printf 'Down,CableUnplugged'
  elif echo "${state_value}" | grep -Eiq '^down$'; then
    printf 'Down,%s' "${physical_value}"
  elif echo "${state_value}" | grep -Eiq '^n/a$' && speed_is_invalid "${speed_value}"; then
    printf 'Down,NoSpeedSelected'
  elif speed_is_invalid "${speed_value}"; then
    printf '%s,InvalidSpeed' "${state_value}"
  else
    printf '%s,%s' "${state_value}" "${physical_value}"
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
  dev_family=$(device_family "${desc}")
  problem_id="${dev_family} ${bdf}"
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
  physical_report=$(friendly_physical_state "${physical}" "${state}")

  problems=()
  fatal_problem=false
  fault_reason=""
  down_state=false
  if [ "${rc}" -ne 0 ]; then
    append_fatal_problem problems fatal_problem "mlxlink failed rc=${rc}"
  fi
  if [ "${state}" = "-" ]; then
    append_problem problems "missing State"
  elif ! echo "${state}" | grep -Eiq 'active|up'; then
    if echo "${state}" | grep -Eiq '^down$'; then
      append_problem problems "state=${state}"
      down_state=true
    else
      append_fatal_problem problems fatal_problem "state=${state}"
    fi
  fi
  if [ "${physical}" = "-" ]; then
    append_problem problems "missing Physical state"
  elif ! echo "${physical}" | grep -Eiq 'linkup|up'; then
    if [ "${down_state}" = "true" ]; then
      if echo "${physical}" | grep -Eiq '^disabled$'; then
        append_fatal_problem problems fatal_problem "physical=${physical_report}"
      else
        append_problem problems "physical=${physical_report}"
      fi
    elif echo "${state}" | grep -Eiq 'active|up' && ! speed_is_invalid "${speed}"; then
      :
    else
      append_fatal_problem problems fatal_problem "physical=${physical_report}"
    fi
  fi
  if speed_is_invalid "${speed}"; then
    if [ "${down_state}" = "true" ]; then
      append_problem problems "speed=${speed}"
    else
      append_fatal_problem problems fatal_problem "speed=${speed}"
    fi
  fi
  if [ -n "${EXPECTED_SPEED}" ] && [ "${speed}" != "${EXPECTED_SPEED}" ]; then
    append_problem problems "expected speed ${EXPECTED_SPEED}, got ${speed}"
  fi
  if grep -Eiq 'Recommendation[[:space:]]*:[[:space:]]*signal not detected|signal not detected' "${mlx_out}"; then
    append_fatal_problem problems fatal_problem "signal not detected"
    fault_reason="signal not detected"
    physical_report="NoSignal"
  fi
  if grep -Eiq 'Recommendation[[:space:]]*:[[:space:]]*Cable is unplugged|Cable is unplugged' "${mlx_out}"; then
    append_fatal_problem problems fatal_problem "cable is unplugged"
    fault_reason="${fault_reason:+${fault_reason};}cable is unplugged"
  fi
  if grep -Eiq 'error|failed|failure|bad|unsupported|no signal|cable.*unplug|module.*bad' "${mlx_out}"; then
    append_problem problems "mlxlink output contains error/warning text"
  fi

  if [ ${#problems[@]} -eq 0 ]; then
    status="OK"
  elif [ "${fatal_problem}" = "true" ]; then
    status="ERROR"
  else
    status="WARN"
  fi

  problem_text=$(join_problems problems)
  condition=$(summary_condition "${state}" "${physical_report}" "${speed}" "${fault_reason}")
  if [ "${problem_text}" != "-" ]; then
    if [ -n "${fault_reason}" ]; then
      append_report_problem "fatal" "${problem_id}: ${condition}|state=${state};physical=${physical_report};speed=${speed};${fault_reason}"
    elif [ "${status}" = "ERROR" ]; then
      append_report_problem "fatal" "${problem_id}: ${condition}|${problem_text}"
    else
      append_report_problem "${status,,}" "${problem_id}: ${condition}|${problem_text}"
    fi
  fi

  ROWS+=( "${status}|${bdf}|${netdevs}|${rdma_devs}|${state}|${physical_report}|${speed}|${width}|${autoneg}|${fec}|$(short_desc "${desc}")|${problem_text}" )
done < "${LSPCI_FILE}"

if [ "${SUMMARY_ONLY}" = "true" ]; then
  echo "Worker Mellanox physical link summary"
else
  echo "Worker Mellanox physical link report"
fi
echo "host: ${HOSTNAME}"
echo "time: ${TIMESTAMP}"
if [ "${SUMMARY_ONLY}" != "true" ]; then
  echo "discovery: lspci $([ "${USE_DOMAIN}" = "true" ] && echo "-D " || true)| grep -i Mel | grep -vi Virt"
  echo "device filter: $([ "${ALL_MELLANOX}" = "true" ] && echo "all non-virtual Mellanox/NVIDIA network devices" || echo "${INCLUDE_REGEX}")"
  if [ -n "${EXPECTED_SPEED}" ]; then
    echo "expected speed: ${EXPECTED_SPEED}"
  fi
fi
echo

if [ ${#ROWS[@]} -eq 0 ]; then
  echo "SUMMARY: ERROR no matching physical CX8/BF3/CX7 Mellanox network links found"
  if [ "${SUMMARY_ONLY}" != "true" ]; then
    echo
    echo "Physical Mellanox devices discovered before CX8/BF3/CX7 filtering:"
    if [ -s "${LSPCI_FILE}" ]; then
      sed 's/^/  /' "${LSPCI_FILE}"
    else
      echo "  none"
    fi
  fi
  exit 1
fi

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

if [ "${SUMMARY_ONLY}" != "true" ]; then
  printf '%-6s %-14s %-18s %-12s %-10s %-14s %-8s %-6s %-8s %-12s %-44s %s\n' \
    "STATUS" "BDF" "NETDEV" "RDMA" "STATE" "PHYSICAL" "SPEED" "WIDTH" "AUTONEG" "FEC" "DEVICE" "PROBLEMS"
  printf '%-6s %-14s %-18s %-12s %-10s %-14s %-8s %-6s %-8s %-12s %-44s %s\n' \
    "------" "---" "------" "----" "-----" "--------" "-----" "-----" "-------" "---" "------" "--------"

  for row in "${ROWS[@]}"; do
    IFS='|' read -r status bdf netdevs rdma_devs state physical speed width autoneg fec desc problem_text <<< "${row}"
    row_color=""
    row_reset=""
    if [ "${status}" = "ERROR" ]; then
      row_color="${RED}"
      row_reset="${RESET}"
    elif [ "${status}" = "WARN" ]; then
      row_color="${YELLOW}"
      row_reset="${RESET}"
    fi
    printf '%s%-6s%s %-14s %s%-18s %-12s %-10s %-14s %-8s %-6s %-8s %-12s %-44s %s%s\n' \
      "${row_color}" "${status}" "${row_reset}" "${bdf}" "${row_color}" "${netdevs}" "${rdma_devs}" "${state}" "${physical}" "${speed}" "${width}" "${autoneg}" "${fec}" "${desc}" "${problem_text}" "${row_reset}"
  done
  echo
fi

echo "SUMMARY: total=${#ROWS[@]} ok=${ok_count} warn=${warn_count} error=${error_count}"

echo
if [ "${SUMMARY_ONLY}" = "true" ]; then
  echo "DETECTED ERRORS:"
else
  echo "DETECTED PROBLEMS:"
fi
printed_problem=false
for problem in "${PROBLEM_LINES[@]}"; do
  severity=${problem%%|*}
  message=${problem#*|}
  if [ "${severity}" = "fatal" ]; then
    if [ "${SUMMARY_ONLY}" = "true" ]; then
      message=${message%%|*}
    else
      message=${message/|/;}
    fi
    print_problem_message "  " "${RED}" "${message}"
    printed_problem=true
  elif [ "${severity}" = "warn" ] && [ "${SUMMARY_ONLY}" != "true" ]; then
    message=${message/|/;}
    print_problem_message "  - " "${YELLOW}" "${message}"
    printed_problem=true
  elif [ "${SUMMARY_ONLY}" != "true" ]; then
    echo "  - ${message}"
    printed_problem=true
  fi
done
if [ "${printed_problem}" = "false" ]; then
  echo "  none"
fi

if [ "${DETAILS}" = "true" ] && [ "${SUMMARY_ONLY}" != "true" ]; then
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
