#!/bin/bash
#
# Generate and optionally apply NVUE L3 gateway patches for routed SR-IOV
# switch ports.
#
# This is intentionally dry-run by default. Pass --apply to copy each generated
# switch-<switch>-<port>-L3.yaml patch to the switch and run nv config patch,
# nv config diff, and nv config apply.
#

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_CONFIG="${SWITCH_CONFIG:-}"
if [ -z "${DEFAULT_CONFIG}" ]; then
  if [ -r "config.yaml" ]; then
    DEFAULT_CONFIG="config.yaml"
  else
    DEFAULT_CONFIG="${SCRIPT_DIR}/debug-switch-fabric.yaml"
  fi
fi

CONFIG_FILE="${DEFAULT_CONFIG}"
GLOBAL_CONFIG="${GLOBAL_OPS_USER:-}"
REPORT_DIR="${REPORT_DIR:-/tmp/netop-switch-fabric-apply-$(date +%Y%m%d_%H%M%S)}"
APPLY=false
FORCE=false
NETWORK_INDEX_FILTER=""
NODE_FILTER=""

function usage()
{
  cat <<EOF
Usage: $0 [--config FILE] [--global-config FILE] [--output-dir DIR] [--apply]
          [--force] [--network-indexes a,b] [--nodes node1,node2]

Generate switch-<switch>-<port>-L3.yaml patches for nv-ipam CIDRPool routed
SR-IOV networks. The script uses:
  - switch YAML for switch/worker SSH credentials and optional defaults
  - global_ops_user.cfg/global_ops.cfg for node pools, device lists, CIDRPools
  - kubectl CIDRPool status for actual per-node gateway allocations
  - worker SSH + lldpcli to map each PF to a switch and port

Options:
  --config FILE          Switch fabric YAML. Default: SWITCH_CONFIG, ./config.yaml,
                         or ops/debug-switch-fabric.yaml.
  --global-config FILE   global_ops_user.cfg to source through global_ops.cfg.
                         Default: GLOBAL_OPS_USER or ./global_ops_user.cfg.
  --output-dir DIR       Directory for generated patches and logs.
  --apply                Copy patches to switches and run nv config patch/diff/apply.
                         Default is dry-run.
  --force                Continue when NETOP_SWITCH_PORT_MODE is not l3.
  --network-indexes LIST Limit to network indexes, for example a,b,h.
  --nodes LIST           Limit to Kubernetes node names.
  -h, --help             Show this help.

Examples:
  $0 --config ops/debug-switch-fabric.yaml --global-config ~/netop-tools/dynamo/global_ops_user.cfg
  $0 --config ops/debug-switch-fabric.yaml --global-config ~/netop-tools/dynamo/global_ops_user.cfg --apply
EOF
}

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

FILTER_NETWORK_INDEXES=()
FILTER_NODES=()

while [ $# -gt 0 ]; do
  case "${1}" in
  --config)
    CONFIG_FILE=${2:-}
    shift 2
    ;;
  --global-config)
    GLOBAL_CONFIG=${2:-}
    shift 2
    ;;
  --output-dir)
    REPORT_DIR=${2:-}
    shift 2
    ;;
  --apply)
    APPLY=true
    shift
    ;;
  --force)
    FORCE=true
    shift
    ;;
  --network-indexes)
    NETWORK_INDEX_FILTER=${2:-}
    append_csv FILTER_NETWORK_INDEXES "${NETWORK_INDEX_FILTER}"
    shift 2
    ;;
  --nodes)
    NODE_FILTER=${2:-}
    append_csv FILTER_NODES "${NODE_FILTER}"
    shift 2
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument ${1}" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [ -z "${NETOP_ROOT_DIR:-}" ]; then
  NETOP_ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  export NETOP_ROOT_DIR
fi

if [ -z "${GLOBAL_CONFIG}" ]; then
  GLOBAL_CONFIG="${NETOP_ROOT_DIR}/global_ops_user.cfg"
fi
if [ ! -r "${GLOBAL_CONFIG}" ]; then
  echo "ERROR: global config not readable: ${GLOBAL_CONFIG}" >&2
  exit 2
fi
if [ ! -r "${NETOP_ROOT_DIR}/global_ops.cfg" ]; then
  echo "ERROR: global_ops.cfg not found under NETOP_ROOT_DIR=${NETOP_ROOT_DIR}" >&2
  exit 2
fi
if [ ! -r "${CONFIG_FILE}" ]; then
  echo "ERROR: switch config not readable: ${CONFIG_FILE}" >&2
  echo "Copy ${SCRIPT_DIR}/debug-switch-fabric.yaml.example to ${SCRIPT_DIR}/debug-switch-fabric.yaml or pass --config." >&2
  exit 2
fi

export GLOBAL_OPS_USER="${GLOBAL_CONFIG}"
# shellcheck source=/dev/null
source "${NETOP_ROOT_DIR}/global_ops.cfg"

K8CL=${K8CL:-kubectl}
read -r -a K8CL_CMD <<< "${K8CL}"

if [ "${NETOP_SWITCH_PORT_MODE,,}" != "l3" ] && [ "${FORCE}" != "true" ]; then
  echo "ERROR: NETOP_SWITCH_PORT_MODE=${NETOP_SWITCH_PORT_MODE:-unset}; expected l3." >&2
  echo "Use --force to generate patches anyway." >&2
  exit 2
fi
if [ "${IPAM_TYPE}" != "nv-ipam" ] || [ "${NVIPAM_POOL_TYPE}" != "CIDRPool" ]; then
  echo "ERROR: L3 switch gateway generation expects IPAM_TYPE=nv-ipam and NVIPAM_POOL_TYPE=CIDRPool." >&2
  echo "Current: IPAM_TYPE=${IPAM_TYPE:-unset} NVIPAM_POOL_TYPE=${NVIPAM_POOL_TYPE:-unset}" >&2
  exit 2
fi

mkdir -p "${REPORT_DIR}"

function kctl()
{
  "${K8CL_CMD[@]}" "$@"
}

function csv_contains()
{
  local value=${1}
  shift
  local item
  for item in "$@"; do
    [ "${item}" = "${value}" ] && return 0
  done
  return 1
}

function safe_file_component()
{
  local value=${1}
  value=${value//[^a-zA-Z0-9_.-]/_}
  value=${value##_}
  value=${value%%_}
  [ -n "${value}" ] || value="switch"
  printf '%s\n' "${value}"
}

function yaml_quote()
{
  local value=${1}
  value=${value//\'/\'\'}
  printf "'%s'" "${value}"
}

function expand_local_path()
{
  local path=${1}
  case "${path}" in
    "~/"*) printf '%s\n' "${HOME}/${path#~/}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

function normalize_id()
{
  local raw=${1}
  raw=${raw#NETOP_NETLIST}
  raw=${raw#_}
  printf '%s\n' "${raw}"
}

function lower()
{
  printf '%s\n' "${1,,}"
}

function add_unique()
{
  local -n out=$1
  local value=${2}
  local item
  [ -n "${value}" ] || return
  for item in "${out[@]}"; do
    [ "${item}" = "${value}" ] && return
  done
  out+=( "${value}" )
}

function parse_switch_config()
{
  SWITCH_CFG_NAMES=()
  SWITCH_CFG_HOSTS=()
  SWITCH_CFG_USERS=()
  SWITCH_CFG_PORTS=()
  SWITCH_CFG_IDENTITIES=()
  SWITCH_CFG_PASSWORDS=()
  SWITCH_CFG_PASSWORD_ENVS=()
  SWITCH_CFG_SERVER_PORTS=()
  DEBUG_CFG_WORKER_SSH_USER=""
  DEBUG_CFG_WORKER_SSH_PORT=""
  DEBUG_CFG_WORKER_SSH_IDENTITY_FILE=""
  DEBUG_CFG_WORKER_SSH_PASSWORD=""
  DEBUG_CFG_WORKER_SSH_OPTS=""
  DEBUG_CFG_SWITCH_L3_PREFIX=""
  DEBUG_CFG_SWITCH_L3_GATEWAY_INDEX=""
  DEBUG_CFG_SWITCH_L3_VRF=""
  DEBUG_CFG_SWITCH_REMOTE_DIR=""

  local parsed="${REPORT_DIR}/switch-config.env"
  python3 - "${CONFIG_FILE}" > "${parsed}" <<'PY'
import re
import shlex
import sys

path = sys.argv[1]

def clean_value(value):
    value = str(value or "").strip()
    if " #" in value:
        value = value.split(" #", 1)[0].rstrip()
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        value = value[1:-1]
    return value

def simple_yaml(path):
    switches = []
    current = None
    section = None
    worker_ssh = {}
    switch_defaults = {}
    key_value = re.compile(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$")

    with open(path, encoding="utf-8") as stream:
        for raw in stream:
            line = raw.rstrip()
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if re.match(r"^switches\s*:\s*$", stripped):
                section = "switches"
                continue
            if re.match(r"^worker_ssh\s*:\s*$", stripped):
                section = "worker_ssh"
                continue
            if re.match(r"^switch_defaults\s*:\s*$", stripped) or re.match(r"^fabric\s*:\s*$", stripped):
                section = "switch_defaults"
                continue

            if section == "worker_ssh":
                if re.match(r"^\S", line):
                    section = None
                    continue
                match = key_value.match(stripped)
                if match:
                    worker_ssh[match.group(1)] = clean_value(match.group(2))
                continue

            if section == "switch_defaults":
                if re.match(r"^\S", line):
                    section = None
                    continue
                match = key_value.match(stripped)
                if match:
                    switch_defaults[match.group(1)] = clean_value(match.group(2))
                continue

            if section == "switches":
                item = re.match(r"^\s*-\s*(.*)$", line)
                if item:
                    if current:
                        switches.append(current)
                    current = {}
                    rest = item.group(1).strip()
                    if rest:
                        match = key_value.match(rest)
                        if match:
                            current[match.group(1)] = clean_value(match.group(2))
                    continue
                if current is not None:
                    match = key_value.match(stripped)
                    if match:
                        current[match.group(1)] = clean_value(match.group(2))

    if current:
        switches.append(current)
    return {"worker_ssh": worker_ssh, "switch_defaults": switch_defaults, "switches": switches}

def list_or_string(value):
    if isinstance(value, (list, tuple)):
        return " ".join(str(item).strip() for item in value if str(item).strip())
    return str(value or "").strip()

try:
    import yaml  # type: ignore
    with open(path, encoding="utf-8") as stream:
        data = yaml.safe_load(stream) or {}
except Exception:
    data = simple_yaml(path)

if isinstance(data, list):
    switches = data
    worker_ssh = {}
    switch_defaults = {}
elif isinstance(data, dict):
    switches = data.get("switches", [])
    worker_ssh = data.get("worker_ssh") or {}
    cluster = data.get("cluster") or {}
    if isinstance(cluster, dict) and not worker_ssh:
        worker_ssh = cluster.get("worker_ssh") or {}
    switch_defaults = data.get("switch_defaults") or data.get("fabric") or {}
else:
    switches = []
    worker_ssh = {}
    switch_defaults = {}

if not isinstance(worker_ssh, dict):
    worker_ssh = {}
if not isinstance(switch_defaults, dict):
    switch_defaults = {}

print(f"DEBUG_CFG_WORKER_SSH_USER={shlex.quote(str(worker_ssh.get('user') or worker_ssh.get('username') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_PORT={shlex.quote(str(worker_ssh.get('port') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_IDENTITY_FILE={shlex.quote(str(worker_ssh.get('identity_file') or worker_ssh.get('identity') or worker_ssh.get('key_file') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_PASSWORD={shlex.quote(str(worker_ssh.get('password') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_OPTS={shlex.quote(str(worker_ssh.get('options') or worker_ssh.get('ssh_opts') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_L3_PREFIX={shlex.quote(str(switch_defaults.get('l3_prefix') or switch_defaults.get('per_node_prefix') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_L3_GATEWAY_INDEX={shlex.quote(str(switch_defaults.get('l3_gateway_index') or switch_defaults.get('gateway_index') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_L3_VRF={shlex.quote(str(switch_defaults.get('l3_vrf') or switch_defaults.get('vrf') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_REMOTE_DIR={shlex.quote(str(switch_defaults.get('remote_dir') or '/tmp').strip())}")

for index, switch in enumerate(switches):
    if not isinstance(switch, dict):
        continue
    host = str(switch.get("host") or switch.get("ip") or switch.get("hostname") or "").strip()
    if not host:
        print(f"# skipping switch entry {index}: missing host/ip", file=sys.stderr)
        continue
    name = str(switch.get("name") or host).strip()
    user = str(switch.get("user") or switch.get("username") or "").strip()
    port = str(switch.get("port") or "").strip()
    identity = str(switch.get("identity_file") or switch.get("identity") or switch.get("key_file") or "").strip()
    password = str(switch.get("password") or "").strip()
    password_env = str(switch.get("password_env") or "").strip()
    server_ports = list_or_string(
        switch.get("server_ports")
        or switch.get("fabric_ports")
        or switch.get("lldp_ports")
        or switch.get("switch_ports")
        or ""
    )
    print(f"SWITCH_CFG_NAMES+=({shlex.quote(name)})")
    print(f"SWITCH_CFG_HOSTS+=({shlex.quote(host)})")
    print(f"SWITCH_CFG_USERS+=({shlex.quote(user)})")
    print(f"SWITCH_CFG_PORTS+=({shlex.quote(port)})")
    print(f"SWITCH_CFG_IDENTITIES+=({shlex.quote(identity)})")
    print(f"SWITCH_CFG_PASSWORDS+=({shlex.quote(password)})")
    print(f"SWITCH_CFG_PASSWORD_ENVS+=({shlex.quote(password_env)})")
    print(f"SWITCH_CFG_SERVER_PORTS+=({shlex.quote(server_ports)})")
PY
  # shellcheck disable=SC1090
  source "${parsed}"

  WORKER_SSH_USER=${WORKER_SSH_USER:-${DEBUG_CFG_WORKER_SSH_USER:-}}
  WORKER_SSH_PORT=${WORKER_SSH_PORT:-${DEBUG_CFG_WORKER_SSH_PORT:-}}
  WORKER_SSH_IDENTITY_FILE=${WORKER_SSH_IDENTITY_FILE:-${DEBUG_CFG_WORKER_SSH_IDENTITY_FILE:-}}
  WORKER_SSH_PASSWORD=${WORKER_SSH_PASSWORD:-${DEBUG_CFG_WORKER_SSH_PASSWORD:-}}
  WORKER_SSH_OPTS=${WORKER_SSH_OPTS:-${DEBUG_CFG_WORKER_SSH_OPTS:-}}
  SWITCH_L3_PREFIX=${SWITCH_L3_PREFIX:-${DEBUG_CFG_SWITCH_L3_PREFIX:-${NETOP_PER_NODE_PREFIX:-}}}
  SWITCH_L3_GATEWAY_INDEX=${SWITCH_L3_GATEWAY_INDEX:-${DEBUG_CFG_SWITCH_L3_GATEWAY_INDEX:-${NETOP_GATEWAY_INDEX:-1}}}
  SWITCH_L3_VRF=${SWITCH_L3_VRF:-${DEBUG_CFG_SWITCH_L3_VRF:-}}
  SWITCH_REMOTE_DIR=${SWITCH_REMOTE_DIR:-${DEBUG_CFG_SWITCH_REMOTE_DIR:-/tmp}}
}

function node_selector_arg()
{
  local key=${1}
  local value=${2}

  if [ -n "${value}" ]; then
    printf '%s=%s\n' "${key}" "${value}"
  else
    printf '%s\n' "${key}"
  fi
}

function nodes_for_selector()
{
  local key=${1}
  local value=${2}
  local selector

  selector=$(node_selector_arg "${key}" "${value}")
  kctl get nodes -l "${selector}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort
}

function resolve_node_ssh_target()
{
  local node=${1}
  local target

  target=$(kctl get node "${node}" \
    -o jsonpath='{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}' \
    2>/dev/null | awk 'NF { print; exit }')

  if [ -n "${target}" ] && [ "${target}" != "<none>" ]; then
    if [ -n "${WORKER_SSH_USER:-}" ] && [[ "${target}" != *@* ]]; then
      printf '%s@%s\n' "${WORKER_SSH_USER}" "${target}"
    else
      printf '%s\n' "${target}"
    fi
  else
    if [ -n "${WORKER_SSH_USER:-}" ] && [[ "${node}" != *@* ]]; then
      printf '%s@%s\n' "${WORKER_SSH_USER}" "${node}"
    else
      printf '%s\n' "${node}"
    fi
  fi
}

function build_worker_ssh_cmd()
{
  WORKER_SSH_CMD=(ssh)
  if [ -n "${SSH_OPTS:-}" ]; then
    # shellcheck disable=SC2206
    WORKER_SSH_CMD+=( ${SSH_OPTS} )
  fi
  if [ -n "${WORKER_SSH_OPTS:-}" ]; then
    # shellcheck disable=SC2206
    WORKER_SSH_CMD+=( ${WORKER_SSH_OPTS} )
  fi
  if [ -n "${WORKER_SSH_PORT:-}" ]; then
    WORKER_SSH_CMD+=( -p "${WORKER_SSH_PORT}" )
  fi
  if [ -n "${WORKER_SSH_IDENTITY_FILE:-}" ]; then
    WORKER_SSH_CMD+=( -i "$(expand_local_path "${WORKER_SSH_IDENTITY_FILE}")" )
  fi
}

function ssh_worker()
{
  local target=${1}
  shift

  build_worker_ssh_cmd
  if [ -n "${WORKER_SSH_PASSWORD:-}" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      echo "ERROR: worker_ssh.password is configured, but sshpass is not installed" >&2
      return 127
    fi
    SSHPASS="${WORKER_SSH_PASSWORD}" sshpass -e "${WORKER_SSH_CMD[@]}" "${target}" "$@"
  else
    "${WORKER_SSH_CMD[@]}" "${target}" "$@"
  fi
}

function discover_lldp_for_bdf()
{
  local node=${1}
  local ssh_target=${2}
  local bdf=${3}
  local cache="${REPORT_DIR}/lldp-${node}-${bdf//[:.]/_}.env"

  if [ -r "${cache}" ]; then
    cat "${cache}"
    return
  fi

  ssh_worker "${ssh_target}" "BDF='${bdf}' bash -s" <<'REMOTE' > "${cache}.tmp" 2>"${cache}.err" || true
set +e
if [ ! -e "/sys/bus/pci/devices/${BDF}" ]; then
  echo "ERROR=missing-pci"
  exit 0
fi
PF="${BDF}"
if [ -e "/sys/bus/pci/devices/${BDF}/physfn" ]; then
  PF=$(basename "$(readlink -f "/sys/bus/pci/devices/${BDF}/physfn" 2>/dev/null)")
fi
for NETPATH in /sys/bus/pci/devices/${PF}/net/*; do
  [ -e "${NETPATH}" ] || continue
  IFACE=$(basename "${NETPATH}")
  if command -v lldpcli >/dev/null 2>&1; then
    KV=$(lldpcli -f keyvalue show neighbors ports "${IFACE}" details 2>/dev/null || \
      lldpcli -f keyvalue show neighbors ports "${IFACE}" 2>/dev/null || true)
    CHASSIS=$(printf '%s\n' "${KV}" | awk -F= '/\.chassis\.name=/ { print $2; exit }')
    PORT=$(printf '%s\n' "${KV}" | awk -F= '/\.port\.ifname=/ { print $2; exit }')
    PORT_DESCR=$(printf '%s\n' "${KV}" | awk -F= '/\.port\.descr=/ { print $2; exit }')
    [ -n "${PORT}" ] || PORT="${PORT_DESCR}"
    if [ -n "${CHASSIS}" ] || [ -n "${PORT}" ]; then
      printf 'PF=%q\n' "${PF}"
      printf 'PF_IFACE=%q\n' "${IFACE}"
      printf 'SWITCH_CHASSIS=%q\n' "${CHASSIS}"
      printf 'SWITCH_PORT=%q\n' "${PORT}"
      exit 0
    fi
  fi
done
echo "ERROR=no-lldp"
REMOTE

  mv "${cache}.tmp" "${cache}"
  cat "${cache}"
}

function cidrpool_gateway()
{
  local pool=${1}
  local node=${2}
  local json

  json=$(kctl -n "${NETOP_NAMESPACE}" get cidrpool.nv-ipam.nvidia.com "${pool}" -o json 2>/dev/null) || return
  python3 -c '
import ipaddress
import json
import sys

node = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)

for allocation in data.get("status", {}).get("allocations", []) or []:
    if allocation.get("nodeName") != node:
        continue
    gateway = allocation.get("gateway") or ""
    prefix = allocation.get("prefix") or ""
    if not gateway or not prefix:
        continue
    try:
        plen = ipaddress.ip_network(prefix, strict=False).prefixlen
    except ValueError:
        continue
    print(f"{gateway}/{plen}")
    raise SystemExit(0)
' "${node}" <<< "${json}"
}

function fallback_gateway()
{
  local network_range=${1}
  local network_position=${2}
  local node_position=${3}
  local prefix=${4}
  local gateway_index=${5}

  python3 - "${network_range}" "${network_position}" "${node_position}" "${prefix}" "${gateway_index}" <<'PY'
import ipaddress
import sys

network_range, network_position, node_position, prefix, gateway_index = sys.argv[1:]
try:
    base = ipaddress.ip_network(network_range, strict=False)
    network_index = int(network_position)
    node_index = int(node_position)
    prefix_len = int(prefix)
    gateway_index_int = int(gateway_index)
    network_start = int(base.network_address) + (base.num_addresses * network_index)
    network = ipaddress.ip_network(f"{ipaddress.ip_address(network_start)}/{base.prefixlen}", strict=False)
    node_blocks = list(network.subnets(new_prefix=prefix_len))
    node_block = node_blocks[node_index]
    gateway = node_block.network_address + gateway_index_int
except Exception:
    raise SystemExit(0)

if gateway not in node_block:
    raise SystemExit(0)
if isinstance(node_block, ipaddress.IPv4Network) and node_block.prefixlen < 31:
    if gateway == node_block.network_address or gateway == node_block.broadcast_address:
        raise SystemExit(0)
print(f"{gateway}/{prefix_len}")
PY
}

function switch_index_for_lldp()
{
  local chassis=${1}
  local port=${2}
  local idx
  local lower_chassis
  local lower_name
  local host
  local server_ports
  local normalized_ports

  lower_chassis=$(lower "${chassis}")
  for idx in "${!SWITCH_CFG_NAMES[@]}"; do
    lower_name=$(lower "${SWITCH_CFG_NAMES[${idx}]}")
    host=$(lower "${SWITCH_CFG_HOSTS[${idx}]}")
    if [ -n "${lower_chassis}" ] && { [ "${lower_chassis}" = "${lower_name}" ] || [ "${lower_chassis}" = "${host}" ]; }; then
      echo "${idx}"
      return
    fi
  done

  local match=""
  for idx in "${!SWITCH_CFG_NAMES[@]}"; do
    normalized_ports="${SWITCH_CFG_SERVER_PORTS[${idx}]:-}"
    normalized_ports="${normalized_ports//,/ }"
    normalized_ports="${normalized_ports//[/ }"
    normalized_ports="${normalized_ports//]/ }"
    normalized_ports="${normalized_ports//\"/ }"
    normalized_ports="${normalized_ports//\'/ }"
    server_ports=" ${normalized_ports} "
    if [[ "${server_ports}" == *" ${port} "* ]]; then
      if [ -n "${match}" ]; then
        echo ""
        return
      fi
      match="${idx}"
    fi
  done
  if [ -n "${match}" ]; then
    echo "${match}"
    return
  fi

  if [ "${#SWITCH_CFG_NAMES[@]}" -eq 1 ]; then
    echo "0"
  fi
}

function build_switch_ssh_cmd()
{
  local idx=${1}
  SWITCH_SSH_CMD=(ssh)
  SWITCH_SCP_CMD=(scp)
  if [ -n "${SSH_OPTS:-}" ]; then
    # shellcheck disable=SC2206
    SWITCH_SSH_CMD+=( ${SSH_OPTS} )
    # shellcheck disable=SC2206
    SWITCH_SCP_CMD+=( ${SSH_OPTS} )
  fi
  if [ -n "${SWITCH_CFG_PORTS[${idx}]}" ]; then
    SWITCH_SSH_CMD+=( -p "${SWITCH_CFG_PORTS[${idx}]}" )
    SWITCH_SCP_CMD+=( -P "${SWITCH_CFG_PORTS[${idx}]}" )
  fi
  if [ -n "${SWITCH_CFG_IDENTITIES[${idx}]}" ]; then
    SWITCH_SSH_CMD+=( -i "$(expand_local_path "${SWITCH_CFG_IDENTITIES[${idx}]}")" )
    SWITCH_SCP_CMD+=( -i "$(expand_local_path "${SWITCH_CFG_IDENTITIES[${idx}]}")" )
  fi
}

function switch_target()
{
  local idx=${1}
  local host="${SWITCH_CFG_HOSTS[${idx}]}"
  local user="${SWITCH_CFG_USERS[${idx}]}"

  if [ -n "${user}" ] && [[ "${host}" != *@* ]]; then
    printf '%s@%s\n' "${user}" "${host}"
  else
    printf '%s\n' "${host}"
  fi
}

function switch_password()
{
  local idx=${1}
  local password="${SWITCH_CFG_PASSWORDS[${idx}]}"
  local password_env="${SWITCH_CFG_PASSWORD_ENVS[${idx}]}"

  if [ -z "${password}" ] && [ -n "${password_env}" ]; then
    password="${!password_env-}"
  fi
  printf '%s\n' "${password}"
}

function write_patch()
{
  local switch_name=${1}
  local switch_host=${2}
  local port=${3}
  local output=${4}
  shift 4
  local gateways=( "$@" )
  local gw

  {
    echo "# Generated by ${0##*/} on $(date -Is)"
    echo "# Switch: ${switch_name} (${switch_host})"
    echo "# Port: ${port}"
    echo "# Purpose: configure L3 gateway address(es) for nv-ipam CIDRPool SR-IOV pod networks."
    echo "# Review with 'sudo nv config diff' before applying."
    echo "- unset:"
    echo "    interface:"
    echo "      ${port}:"
    echo "        bridge:"
    echo "          domain:"
    echo "            br_default: {}"
    echo "- set:"
    echo "    interface:"
    echo "      ${port}:"
    echo "        type: swp"
    if [ -n "${SWITCH_L3_VRF:-}" ] || [ ${#gateways[@]} -gt 0 ]; then
      echo "        ip:"
      if [ -n "${SWITCH_L3_VRF:-}" ]; then
        echo "          vrf: ${SWITCH_L3_VRF}"
      fi
      if [ ${#gateways[@]} -gt 0 ]; then
        echo "          address:"
        for gw in "${gateways[@]}"; do
          echo "            ${gw}: {}"
        done
      fi
    fi
  } > "${output}"
}

function apply_patch_to_switch()
{
  local idx=${1}
  local file=${2}
  local target
  local remote_file
  local password

  target=$(switch_target "${idx}")
  remote_file="${SWITCH_REMOTE_DIR%/}/$(basename "${file}")"
  password=$(switch_password "${idx}")
  build_switch_ssh_cmd "${idx}"

  if [ -n "${password}" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      echo "ERROR: switch password/password_env is configured, but sshpass is not installed" >&2
      return 127
    fi
    echo "APPLY ${file} -> ${target}:${remote_file}"
    SSHPASS="${password}" sshpass -e "${SWITCH_SCP_CMD[@]}" "${file}" "${target}:${remote_file}"
    SSHPASS="${password}" sshpass -e "${SWITCH_SSH_CMD[@]}" "${target}" \
      "sudo nv config patch '${remote_file}' && sudo nv config diff && sudo nv config apply"
  else
    echo "APPLY ${file} -> ${target}:${remote_file}"
    "${SWITCH_SCP_CMD[@]}" "${file}" "${target}:${remote_file}"
    "${SWITCH_SSH_CMD[@]}" "${target}" \
      "sudo nv config patch '${remote_file}' && sudo nv config diff && sudo nv config apply"
  fi
}

parse_switch_config

if [ ${#SWITCH_CFG_HOSTS[@]} -eq 0 ]; then
  echo "ERROR: no switches found in ${CONFIG_FILE}" >&2
  exit 2
fi
if [ -z "${SWITCH_L3_PREFIX:-}" ]; then
  echo "ERROR: no L3 prefix found. Set NETOP_PER_NODE_PREFIX, SWITCH_L3_PREFIX, or switch_defaults.l3_prefix." >&2
  exit 2
fi

SUMMARY="${REPORT_DIR}/summary.txt"
PLAN="${REPORT_DIR}/plan.tsv"
PATCH_LIST="${REPORT_DIR}/patches.txt"
WARNINGS="${REPORT_DIR}/warnings.txt"
: > "${PLAN}"
: > "${PATCH_LIST}"
: > "${WARNINGS}"

echo "Mode: $([ "${APPLY}" = "true" ] && echo apply || echo dry-run)"
echo "Switch config: ${CONFIG_FILE}"
echo "Global config: ${GLOBAL_CONFIG}"
echo "Output dir: ${REPORT_DIR}"
echo "Network range: ${NETOP_NETWORK_RANGE}"
echo "Gateway index: ${SWITCH_L3_GATEWAY_INDEX}"
echo "Per-node prefix: ${SWITCH_L3_PREFIX}"
echo "VRF: ${SWITCH_L3_VRF:-<unset>}"
echo

POOL_SOURCES=()
if declare -p NETOP_NODEPOOLS >/dev/null 2>&1 && [ ${#NETOP_NODEPOOLS[@]} -gt 0 ]; then
  POOL_SOURCES=( "${NETOP_NODEPOOLS[@]}" )
else
  POOL_SOURCES=( "NETOP_NETLIST" )
fi
SU_VALUES=()
if declare -p NETOP_SULIST >/dev/null 2>&1; then
  SU_VALUES=( "${NETOP_SULIST[@]}" )
fi
if [ ${#SU_VALUES[@]} -eq 0 ]; then
  SU_VALUES=( "" )
fi

for pool_source in "${POOL_SOURCES[@]}"; do
  pool_id=$(normalize_id "${pool_source}")
  if [ -n "${pool_id}" ]; then
    netlist_var="NETOP_NETLIST_${pool_id}"
    selector_var="NETOP_NODESELECTOR_${pool_id}"
    selector_val_var="NETOP_NODESELECTOR_VAL_${pool_id}"
    fabric_var="NETOP_FABRIC_${pool_id}"
  else
    netlist_var="NETOP_NETLIST"
    selector_var="NETOP_NODESELECTOR"
    selector_val_var="NETOP_NODESELECTOR_VAL"
    fabric_var=""
  fi

  if ! declare -p "${netlist_var}" >/dev/null 2>&1; then
    echo "WARN: ${netlist_var} is not defined; skipping ${pool_source}" | tee -a "${WARNINGS}" >&2
    continue
  fi

  eval "POOL_NETLIST=( \"\${${netlist_var}[@]}\" )"
  selector_key="${!selector_var:-${NETOP_NODESELECTOR:-node-role.kubernetes.io/worker}}"
  selector_val="${!selector_val_var:-${NETOP_NODESELECTOR_VAL:-}}"
  fabric=""
  network_range="${NETOP_NETWORK_RANGE}"
  if [ -n "${fabric_var}" ]; then
    fabric="${!fabric_var:-}"
    if [ -n "${fabric}" ]; then
      range_var="NETOP_NETWORK_RANGE_${fabric//-/_}"
      network_range="${!range_var:-${NETOP_NETWORK_RANGE}}"
    fi
  fi

  mapfile -t POOL_NODES < <(nodes_for_selector "${selector_key}" "${selector_val}")
  if [ ${#FILTER_NODES[@]} -gt 0 ]; then
    FILTERED_NODES=()
    for node in "${POOL_NODES[@]}"; do
      csv_contains "${node}" "${FILTER_NODES[@]}" && FILTERED_NODES+=( "${node}" )
    done
    POOL_NODES=( "${FILTERED_NODES[@]}" )
  fi
  if [ ${#POOL_NODES[@]} -eq 0 ]; then
    echo "WARN: no nodes matched selector $(node_selector_arg "${selector_key}" "${selector_val}") for ${pool_source}" | tee -a "${WARNINGS}" >&2
    continue
  fi

  for node_pos in "${!POOL_NODES[@]}"; do
    node="${POOL_NODES[${node_pos}]}"
    ssh_target=$(resolve_node_ssh_target "${node}")
    for net_pos in "${!POOL_NETLIST[@]}"; do
      entry="${POOL_NETLIST[${net_pos}]}"
      nidx="${entry%%,*}"
      if [ ${#FILTER_NETWORK_INDEXES[@]} -gt 0 ] && ! csv_contains "${nidx}" "${FILTER_NETWORK_INDEXES[@]}"; then
        continue
      fi
      device_fields=$(echo "${entry}" | cut -d',' -f4- | sed 's/,$//')
      bdf="${device_fields%%,*}"
      if [ -z "${bdf}" ]; then
        echo "WARN: ${pool_source}/${nidx} has no BDF in ${entry}; skipping" | tee -a "${WARNINGS}" >&2
        continue
      fi

      lldp_env=$(discover_lldp_for_bdf "${node}" "${ssh_target}" "${bdf}")
      SWITCH_CHASSIS=""
      SWITCH_PORT=""
      PF=""
      PF_IFACE=""
      ERROR=""
      # shellcheck disable=SC1090
      eval "${lldp_env}"
      if [ -n "${ERROR:-}" ] || [ -z "${SWITCH_PORT:-}" ]; then
        echo "WARN: LLDP discovery failed for ${node}/${bdf}: ${ERROR:-missing switch port}" | tee -a "${WARNINGS}" >&2
        continue
      fi

      switch_idx=$(switch_index_for_lldp "${SWITCH_CHASSIS}" "${SWITCH_PORT}")
      if [ -z "${switch_idx}" ]; then
        echo "WARN: no switch config entry matched LLDP chassis=${SWITCH_CHASSIS} port=${SWITCH_PORT} for ${node}/${bdf}" | tee -a "${WARNINGS}" >&2
        continue
      fi

      for su in "${SU_VALUES[@]}"; do
        sutag=${su:+-${su}}
        pool_name="${NETOP_NETWORK_POOL}-${nidx}${sutag}"
        gw=$(cidrpool_gateway "${pool_name}" "${node}")
        gw_source="cidrpool-status"
        if [ -z "${gw}" ]; then
          gw=$(fallback_gateway "${network_range}" "${net_pos}" "${node_pos}" "${SWITCH_L3_PREFIX}" "${SWITCH_L3_GATEWAY_INDEX}")
          gw_source="fallback-node-order"
          echo "WARN: no CIDRPool allocation found for ${pool_name}/${node}; fallback gateway=${gw:-missing}" | tee -a "${WARNINGS}" >&2
        fi
        if [ -z "${gw}" ]; then
          echo "WARN: unable to determine gateway for ${pool_name}/${node}; skipping" | tee -a "${WARNINGS}" >&2
          continue
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "${switch_idx}" "${SWITCH_CFG_NAMES[${switch_idx}]}" "${SWITCH_CFG_HOSTS[${switch_idx}]}" \
          "${SWITCH_PORT}" "${gw}" "${node}" "${pool_name}" "${nidx}" "${bdf}" "${PF_IFACE}" "${gw_source}" \
          >> "${PLAN}"
      done
    done
  done
done

if [ ! -s "${PLAN}" ]; then
  echo "ERROR: no switch gateway changes were planned. See ${WARNINGS}" >&2
  exit 1
fi

python3 - "${PLAN}" "${REPORT_DIR}" "${PATCH_LIST}" "${SWITCH_L3_VRF}" <<'PY'
import collections
import os
import re
import sys

plan, report_dir, patch_list, _vrf = sys.argv[1:]
groups = collections.OrderedDict()
rows = []
with open(plan, encoding="utf-8") as stream:
    for line in stream:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 11:
            continue
        rows.append(parts)
        key = tuple(parts[:4])
        groups.setdefault(key, [])
        if parts[4] not in groups[key]:
            groups[key].append(parts[4])

def safe(value):
    value = re.sub(r"[^a-zA-Z0-9_.-]", "_", value)
    return value.strip("_") or "switch"

with open(patch_list, "w", encoding="utf-8") as out:
    for (idx, name, host, port), _gateways in groups.items():
        path = os.path.join(report_dir, f"switch-{safe(name)}-{safe(port)}-L3.yaml")
        out.write("\t".join([idx, name, host, port, path]) + "\n")
PY

while IFS=$'\t' read -r switch_idx switch_name switch_host port patch_file; do
  mapfile -t gateways < <(awk -F'\t' -v idx="${switch_idx}" -v port="${port}" '$1 == idx && $4 == port { print $5 }' "${PLAN}" | awk 'NF && !seen[$0]++ { print }')
  write_patch "${switch_name}" "${switch_host}" "${port}" "${patch_file}" "${gateways[@]}"
done < "${PATCH_LIST}"

{
  echo "Switch L3 gateway apply report"
  echo "time: $(date -Is)"
  echo "mode: $([ "${APPLY}" = "true" ] && echo apply || echo dry-run)"
  echo "switch_config: ${CONFIG_FILE}"
  echo "global_config: ${GLOBAL_CONFIG}"
  echo "netop_namespace: ${NETOP_NAMESPACE}"
  echo "switch_l3_prefix: ${SWITCH_L3_PREFIX}"
  echo "switch_l3_gateway_index: ${SWITCH_L3_GATEWAY_INDEX}"
  echo "switch_l3_vrf: ${SWITCH_L3_VRF:-}"
  echo
  echo "planned gateways:"
  awk -F'\t' '{ printf "  switch=%s host=%s port=%s gateway=%s node=%s pool=%s net=%s bdf=%s pf_iface=%s source=%s\n", $2, $3, $4, $5, $6, $7, $8, $9, $10, $11 }' "${PLAN}"
  echo
  echo "generated patches:"
  awk -F'\t' '{ print "  " $5 }' "${PATCH_LIST}"
  if [ -s "${WARNINGS}" ]; then
    echo
    echo "warnings:"
    sed 's/^/  /' "${WARNINGS}"
  fi
} > "${SUMMARY}"

cat "${SUMMARY}"

if [ "${APPLY}" = "true" ]; then
  echo
  echo "Applying generated switch patches..."
  while IFS=$'\t' read -r switch_idx _switch_name _switch_host _port patch_file; do
    apply_patch_to_switch "${switch_idx}" "${patch_file}"
  done < "${PATCH_LIST}"
else
  echo
  echo "Dry-run only. Review generated files, then re-run with --apply to patch switches."
fi
