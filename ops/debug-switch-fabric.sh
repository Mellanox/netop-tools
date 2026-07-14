#!/bin/bash
#
# Map two pod SR-IOV interfaces to host PF/VF state and switch MAC checks.
#
# This script is read-only. It uses kubectl for pod data and ssh for host/switch
# data. It uses lldpcli on each host PF to identify the connected switch and
# switch port. If SWITCH_HOSTS is set, it also runs a few read-only MAC table
# commands on each switch.
#
set -u

K8CL=${K8CL:-kubectl}
NETOP_NAMESPACE=${NETOP_NAMESPACE:-nvidia-network-operator}
PING_COUNT=${PING_COUNT:-2}
PING_TIMEOUT=${PING_TIMEOUT:-1}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_SWITCH_CONFIG="${SCRIPT_DIR}/debug-switch-fabric.yaml"
SWITCH_CONFIG=${SWITCH_CONFIG:-${DEFAULT_SWITCH_CONFIG}}

function usage()
{
  cat <<EOF
usage: $0 SRC_POD DST_POD [namespace] [interface]

Examples:
  $0 test2-05-1 test1-05-1 default net2

Environment:
  K8CL             kubectl command to use. Default: kubectl
  NETOP_NAMESPACE  Network Operator namespace. Default: nvidia-network-operator
  SWITCH_CONFIG    Optional switch YAML. Default: ops/debug-switch-fabric.yaml
                   Supports worker_ssh and switches sections.
  SWITCH_HOSTS     Optional space-separated switch ssh targets. Appended to YAML switches
  SWITCH_BRIDGE_DOMAIN Optional bridge domain for generated switch-<name>-<port>-vlan0-L2.yaml files. Default: br_default
  SWITCH_L2_VLAN   Optional native/access VLAN for vlan 0 untagged pod traffic. Default: 1
  SWITCH_L3_GATEWAYS Optional true/false. When true, generated switch-<name>-<port>-L3.yaml files
                   include per-port gateway IPs computed from pod IP, SWITCH_L3_PREFIX,
                   and SWITCH_L3_GATEWAY_INDEX.
  SWITCH_L3_PREFIX Optional per-node prefix length for L3 gateway generation.
                   Defaults to NETOP_PER_NODE_PREFIX when set.
  SWITCH_L3_GATEWAY_INDEX Optional gateway host index inside each per-node prefix.
                   Defaults to NETOP_GATEWAY_INDEX when set, otherwise 1.
  SWITCH_L3_VRF    Optional VRF name to include in generated L3 gateway patches.
  REPORT_DIR       Existing or new output directory. Default: /tmp/netop-switch-fabric-<timestamp>
  SSH_OPTS         Optional ssh options used for worker and switch logins
EOF
  exit 1
}

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
  usage
fi

SRC_POD=${1}
shift
DST_POD=${1}
shift
if [ $# -gt 0 ]; then
  NS=${1}
  shift
else
  NS=default
fi
IFACE=${1:-net2}

REPORT_DIR=${REPORT_DIR:-/tmp/netop-switch-fabric-$(date +%Y%m%d_%H%M%S)}
mkdir -p "${REPORT_DIR}"
SUMMARY="${REPORT_DIR}/summary.txt"

function run_log()
{
  local name=${1}
  local file=${2}
  shift 2
  {
    echo
    echo "### ${name}"
    echo "# $(date -Is)"
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >> "${file}" 2>&1 || true
}

function pod_exec_log()
{
  local pod=${1}
  local name=${2}
  local file=${3}
  local cmd=${4}
  {
    echo
    echo "### ${pod}: ${name}"
    echo "# $(date -Is)"
    echo "$ ${K8CL} -n ${NS} exec ${pod} -- sh -c ${cmd}"
    ${K8CL} -n "${NS}" exec "${pod}" -- sh -c "${cmd}"
  } >> "${file}" 2>&1 || true
}

function pod_rdma_cmd()
{
  local iface=${1}
  local rdma_dev=${2:-}

  cat <<EOF
echo "rdma link:";
if command -v rdma >/dev/null 2>&1; then
  rdma link || true;
  if [ -n "${iface}" ] && [ "${iface}" != "all" ]; then
    echo;
    echo "rdma link show netdev ${iface}:";
    rdma link show netdev ${iface} 2>/dev/null || true;
  fi;
  echo;
  echo "rdma dev show:";
  rdma dev show 2>/dev/null || true;
else
  echo "rdma not found";
fi;
echo;
echo "ibv_devices:";
if command -v ibv_devices >/dev/null 2>&1; then
  ibv_devices || true;
else
  echo "ibv_devices not found";
fi;
echo;
echo "ibv_devinfo:";
if command -v ibv_devinfo >/dev/null 2>&1; then
  if [ -n "${rdma_dev}" ]; then
    ibv_devinfo -d "${rdma_dev}" 2>/dev/null || ibv_devinfo || true;
  else
    ibv_devinfo || true;
  fi;
else
  echo "ibv_devinfo not found";
fi;
echo;
echo "ibv_info:";
if command -v ibv_info >/dev/null 2>&1; then
  ibv_info || true;
else
  echo "ibv_info not found";
fi;
echo;
echo "show_gids:";
if command -v show_gids >/dev/null 2>&1; then
  if [ -n "${rdma_dev}" ]; then
    show_gids -d "${rdma_dev}" 2>/dev/null || show_gids || true;
  else
    show_gids || true;
  fi;
else
  echo "show_gids not found";
fi;
echo;
echo "sysfs GUID/GID checks:";
if [ -n "${rdma_dev}" ] && [ -d "/sys/class/infiniband/${rdma_dev}" ]; then
  echo "device: ${rdma_dev}";
  for f in node_guid sys_image_guid board_id fw_ver hca_type; do
    if [ -r "/sys/class/infiniband/${rdma_dev}/\${f}" ]; then
      val=\$(cat "/sys/class/infiniband/${rdma_dev}/\${f}" 2>/dev/null);
      echo "\${f}: \${val}";
      case "\${f}" in
      node_guid|sys_image_guid)
        if echo "\${val}" | grep -Eq '^(00:){7}00$|^(0000:){3}0000$|^0+$'; then
          echo "WARN: ${rdma_dev} \${f} is all zero";
        fi
        ;;
      esac;
    fi;
  done;
  for port in /sys/class/infiniband/${rdma_dev}/ports/*; do
    [ -d "\${port}" ] || continue;
    p=\$(basename "\${port}");
    echo "port \${p}:";
    for f in state phys_state link_layer rate lid sm_lid; do
      [ -r "\${port}/\${f}" ] && echo "  \${f}: \$(cat "\${port}/\${f}" 2>/dev/null)";
    done;
    echo "  gids:";
    for gid in "\${port}"/gids/*; do
      [ -r "\${gid}" ] || continue;
      idx=\$(basename "\${gid}");
      val=\$(cat "\${gid}" 2>/dev/null);
      type="";
      ndev="";
      [ -r "\${port}/gid_attrs/types/\${idx}" ] && type=\$(cat "\${port}/gid_attrs/types/\${idx}" 2>/dev/null);
      [ -r "\${port}/gid_attrs/ndevs/\${idx}" ] && ndev=\$(cat "\${port}/gid_attrs/ndevs/\${idx}" 2>/dev/null);
      echo "    [\${idx}] \${val} type=\${type} ndev=\${ndev}";
      if echo "\${val}" | grep -Eq '^::\$|^0:0:0:0:0:0:0:0\$|^0000:0000:0000:0000:0000:0000:0000:0000\$'; then
        echo "    WARN: GID index \${idx} is all zero";
      fi;
    done;
  done;
elif [ -n "${rdma_dev}" ]; then
  echo "WARN: /sys/class/infiniband/${rdma_dev} not found";
else
  echo "No RDMA device name available from network-status";
fi
EOF
}

function pod_jsonpath()
{
  local pod=${1}
  local path=${2}
  ${K8CL} -n "${NS}" get pod "${pod}" -o jsonpath="${path}"
}

function get_network_status()
{
  local pod=${1}
  local file=${2}
  ${K8CL} -n "${NS}" get pod "${pod}" \
    -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
    > "${file}" 2>"${file}.err" || true
}

function parse_endpoint()
{
  local status_file=${1}
  python3 - "${status_file}" "${IFACE}" <<'PY'
import json
import sys

path, iface = sys.argv[1:3]
raw = open(path, encoding="utf-8").read().strip()
entries = json.loads(raw) if raw else []
for entry in entries:
    if entry.get("interface") != iface:
        continue
    pci = entry.get("device-info", {}).get("pci", {}).get("pci-address", "")
    rdma = entry.get("device-info", {}).get("pci", {}).get("rdma-device", "")
    ip = (entry.get("ips") or [""])[0]
    fields = [
        entry.get("name", ""),
        entry.get("interface", ""),
        ip,
        entry.get("mac", ""),
        pci,
        rdma,
    ]
    print("\t".join(fields))
    break
PY
}

function load_switch_config()
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
  DEBUG_CFG_SWITCH_BRIDGE_DOMAIN=""
  DEBUG_CFG_SWITCH_L2_VLAN=""
  DEBUG_CFG_SWITCH_L3_GATEWAYS=""
  DEBUG_CFG_SWITCH_L3_PREFIX=""
  DEBUG_CFG_SWITCH_L3_GATEWAY_INDEX=""
  DEBUG_CFG_SWITCH_L3_VRF=""

  if [ -r "${SWITCH_CONFIG}" ]; then
    local parsed="${REPORT_DIR}/switch-config.env"
    python3 - "${SWITCH_CONFIG}" > "${parsed}" <<'PY'
import re
import shlex
import sys

path = sys.argv[1]

def clean_value(value):
    value = value.strip()
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

worker_ssh = {}
switch_defaults = {}
if isinstance(data, dict):
    worker_ssh = data.get("worker_ssh") or {}
    cluster = data.get("cluster") or {}
    if isinstance(cluster, dict) and not worker_ssh:
        worker_ssh = cluster.get("worker_ssh") or {}
    switch_defaults = data.get("switch_defaults") or data.get("fabric") or {}
if not isinstance(worker_ssh, dict):
    worker_ssh = {}
if not isinstance(switch_defaults, dict):
    switch_defaults = {}

print(f"DEBUG_CFG_WORKER_SSH_USER={shlex.quote(str(worker_ssh.get('user') or worker_ssh.get('username') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_PORT={shlex.quote(str(worker_ssh.get('port') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_IDENTITY_FILE={shlex.quote(str(worker_ssh.get('identity_file') or worker_ssh.get('identity') or worker_ssh.get('key_file') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_PASSWORD={shlex.quote(str(worker_ssh.get('password') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_OPTS={shlex.quote(str(worker_ssh.get('options') or worker_ssh.get('ssh_opts') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_BRIDGE_DOMAIN={shlex.quote(str(switch_defaults.get('bridge_domain') or switch_defaults.get('bridge') or 'br_default').strip())}")
print(f"DEBUG_CFG_SWITCH_L2_VLAN={shlex.quote(str(switch_defaults.get('l2_vlan') or switch_defaults.get('native_vlan') or switch_defaults.get('untagged_vlan') or '1').strip())}")
print(f"DEBUG_CFG_SWITCH_L3_GATEWAYS={shlex.quote(str(switch_defaults.get('l3_gateways') or switch_defaults.get('l3_gateway_addresses') or switch_defaults.get('generate_l3_gateways') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_L3_PREFIX={shlex.quote(str(switch_defaults.get('l3_prefix') or switch_defaults.get('per_node_prefix') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_L3_GATEWAY_INDEX={shlex.quote(str(switch_defaults.get('l3_gateway_index') or switch_defaults.get('gateway_index') or '').strip())}")
print(f"DEBUG_CFG_SWITCH_L3_VRF={shlex.quote(str(switch_defaults.get('l3_vrf') or switch_defaults.get('vrf') or '').strip())}")

if isinstance(data, list):
    switches = data
elif isinstance(data, dict):
    switches = data.get("switches", [])
else:
    switches = []

for index, switch in enumerate(switches):
    if not isinstance(switch, dict):
        continue

    host = str(
        switch.get("host")
        or switch.get("ip")
        or switch.get("hostname")
        or ""
    ).strip()
    if not host:
        print(f"# skipping switch entry {index}: missing host/ip", file=sys.stderr)
        continue

    name = str(switch.get("name") or host).strip()
    user = str(switch.get("user") or switch.get("username") or "").strip()
    port = str(switch.get("port") or "").strip()
    identity = str(
        switch.get("identity_file")
        or switch.get("identity")
        or switch.get("key_file")
        or ""
    ).strip()
    password_env = str(switch.get("password_env") or "").strip()
    password = str(switch.get("password") or "").strip()
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
  fi

  WORKER_SSH_USER=${WORKER_SSH_USER:-${DEBUG_CFG_WORKER_SSH_USER:-}}
  WORKER_SSH_PORT=${WORKER_SSH_PORT:-${DEBUG_CFG_WORKER_SSH_PORT:-}}
  WORKER_SSH_IDENTITY_FILE=${WORKER_SSH_IDENTITY_FILE:-${DEBUG_CFG_WORKER_SSH_IDENTITY_FILE:-}}
  WORKER_SSH_PASSWORD=${WORKER_SSH_PASSWORD:-${DEBUG_CFG_WORKER_SSH_PASSWORD:-}}
  WORKER_SSH_OPTS=${WORKER_SSH_OPTS:-${DEBUG_CFG_WORKER_SSH_OPTS:-}}
  SWITCH_BRIDGE_DOMAIN=${SWITCH_BRIDGE_DOMAIN:-${DEBUG_CFG_SWITCH_BRIDGE_DOMAIN:-br_default}}
  SWITCH_L2_VLAN=${SWITCH_L2_VLAN:-${DEBUG_CFG_SWITCH_L2_VLAN:-1}}
  SWITCH_L3_GATEWAYS=${SWITCH_L3_GATEWAYS:-${DEBUG_CFG_SWITCH_L3_GATEWAYS:-false}}
  SWITCH_L3_PREFIX=${SWITCH_L3_PREFIX:-${DEBUG_CFG_SWITCH_L3_PREFIX:-${NETOP_PER_NODE_PREFIX:-}}}
  SWITCH_L3_GATEWAY_INDEX=${SWITCH_L3_GATEWAY_INDEX:-${DEBUG_CFG_SWITCH_L3_GATEWAY_INDEX:-${NETOP_GATEWAY_INDEX:-1}}}
  SWITCH_L3_VRF=${SWITCH_L3_VRF:-${DEBUG_CFG_SWITCH_L3_VRF:-}}

  if [ -n "${SWITCH_HOSTS:-}" ]; then
    local sw
    for sw in ${SWITCH_HOSTS}; do
      SWITCH_CFG_NAMES+=( "${sw}" )
      SWITCH_CFG_HOSTS+=( "${sw}" )
      SWITCH_CFG_USERS+=( "" )
      SWITCH_CFG_PORTS+=( "" )
      SWITCH_CFG_IDENTITIES+=( "" )
      SWITCH_CFG_PASSWORDS+=( "" )
      SWITCH_CFG_PASSWORD_ENVS+=( "" )
      SWITCH_CFG_SERVER_PORTS+=( "" )
    done
  fi
}

function expand_local_path()
{
  local path=${1}
  case "${path}" in
    "~/"*) printf '%s\n' "${HOME}/${path#~/}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

function safe_file_component()
{
  local value=${1}
  value=${value//[^a-zA-Z0-9_.-]/_}
  value=${value##_}
  value=${value%%_}
  if [ -z "${value}" ]; then
    value="switch"
  fi
  printf '%s\n' "${value}"
}

function yaml_quote()
{
  local value=${1}
  value=${value//\'/\'\'}
  printf "'%s'" "${value}"
}

function is_true()
{
  local value=${1:-}
  case "${value,,}" in
    1|true|yes|y|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

function normalize_port_list()
{
  local value=${1:-}
  value=${value//,/ }
  value=${value//[/ }
  value=${value//]/ }
  value=${value//\"/ }
  value=${value//\'/ }
  # shellcheck disable=SC2086
  printf '%s\n' ${value} 2>/dev/null | awk 'NF && !seen[$0]++ { print }' | xargs 2>/dev/null || true
}

function select_switch_l3_gateways()
{
  local switch_name=${1}
  local switch_host=${2}
  local switch_count=${3}
  local explicit_ports=${4}

  if ! is_true "${SWITCH_L3_GATEWAYS:-false}"; then
    return
  fi
  if [ -z "${SWITCH_L3_PREFIX:-}" ]; then
    return
  fi

  python3 - "${switch_name}" "${switch_host}" "${switch_count}" \
    "${explicit_ports}" "${SWITCH_L3_PREFIX}" "${SWITCH_L3_GATEWAY_INDEX}" \
    "${SRC_POD}" "${SRC_NODE}" "${SRC_IP}" \
    "${DST_POD}" "${DST_NODE}" "${DST_IP}" \
    "${REPORT_DIR}/source-host.txt" "${REPORT_DIR}/dest-host.txt" <<'PY'
import ipaddress
import re
import sys

(
    name,
    host,
    switch_count,
    explicit_ports,
    prefix,
    gateway_index,
    src_pod,
    src_node,
    src_ip,
    dst_pod,
    dst_node,
    dst_ip,
    src_file,
    dst_file,
) = sys.argv[1:]

try:
    prefix_int = int(prefix)
    gateway_index_int = int(gateway_index)
except ValueError:
    raise SystemExit(0)

def norm(value):
    value = (value or "").strip().lower()
    if "@" in value:
        value = value.rsplit("@", 1)[1]
    return value

def host_short(value):
    return norm(value).split(".", 1)[0]

def split_ports(value):
    return {
        port
        for port in re.split(r"[\s,\[\]'\"]+", value or "")
        if port
    }

def gateway_cidr(ip):
    try:
        iface = ipaddress.ip_interface(f"{ip}/{prefix_int}")
        network = iface.network
        gateway = network.network_address + gateway_index_int
    except ValueError:
        return ""

    if gateway not in network:
        return ""
    if isinstance(network, ipaddress.IPv4Network) and network.prefixlen < 31:
        if gateway == network.network_address or gateway == network.broadcast_address:
            return ""
    return f"{gateway}/{prefix_int}"

def split_records(path):
    records = {}
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return records
    for line in lines:
        if not line.startswith("lldp.") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        parts = key.split(".")
        if len(parts) < 3:
            continue
        record_id = ".".join(parts[:2])
        field = ".".join(parts[2:])
        records.setdefault(record_id, {})[field] = value.strip()
    return records

name_norm = norm(name)
host_norm = norm(host)
name_short = host_short(name)
host_short_name = host_short(host)
explicit_port_set = split_ports(explicit_ports)

endpoints = [
    ("source", src_pod, src_node, src_ip, src_file),
    ("dest", dst_pod, dst_node, dst_ip, dst_file),
]
seen = set()

for endpoint, pod, node, ip, path in endpoints:
    gw = gateway_cidr(ip)
    if not gw:
        continue
    for rec in split_records(path).values():
        port = rec.get("port.ifname") or rec.get("port.descr") or ""
        if not port:
            continue

        candidates = []
        for key, value in rec.items():
            if key.startswith("chassis.") or key in {"system.name", "hostname"}:
                candidates.append(value)
        candidate_norms = [norm(candidate) for candidate in candidates if candidate]
        candidate_shorts = [host_short(candidate) for candidate in candidates if candidate]

        matched = port in explicit_port_set
        if not matched:
            matched = (
                name_norm in candidate_norms
                or host_norm in candidate_norms
                or name_short in candidate_shorts
                or host_short_name in candidate_shorts
            )
        if not matched and switch_count == "1":
            matched = True
        if not matched:
            continue

        key = (port, gw)
        if key in seen:
            continue
        seen.add(key)
        print("\t".join([port, gw, endpoint, pod, node, ip]))
PY
}

function l3_gateway_for_port()
{
  local port=${1}
  local records=${2}

  awk -F'\t' -v port="${port}" '$1 == port { print; exit }' "${records}" 2>/dev/null || true
}

function select_switch_fix_ports()
{
  local switch_name=${1}
  local switch_host=${2}
  local explicit_ports=${3}
  local discovered_ports=${4}
  local switch_count=${5}

  python3 - "${switch_name}" "${switch_host}" "${explicit_ports}" "${discovered_ports}" "${switch_count}" \
    "${REPORT_DIR}/source-host.txt" "${REPORT_DIR}/dest-host.txt" <<'PY'
import re
import sys

name, host, explicit, discovered, switch_count, *paths = sys.argv[1:]

def split_ports(value):
    ports = re.split(r"[\s,\[\]'\"]+", value or "")
    out = []
    for port in ports:
        if port and port not in out:
            out.append(port)
    return out

explicit_ports = split_ports(explicit)
if explicit_ports:
    print(" ".join(explicit_ports))
    raise SystemExit(0)

def norm(value):
    value = (value or "").strip().lower()
    if "@" in value:
        value = value.rsplit("@", 1)[1]
    return value

def host_short(value):
    return norm(value).split(".", 1)[0]

name_norm = norm(name)
host_norm = norm(host)
name_short = host_short(name)
host_short_name = host_short(host)

records = {}
for path in paths:
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    for line in lines:
        if not line.startswith("lldp.") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        parts = key.split(".")
        if len(parts) < 3:
            continue
        prefix = ".".join(parts[:2])
        field = ".".join(parts[2:])
        records.setdefault(prefix, {})[field] = value.strip()

matched = []
for rec in records.values():
    port = rec.get("port.ifname") or rec.get("port.descr") or ""
    if not port:
        continue

    candidates = []
    for key, value in rec.items():
        if key.startswith("chassis.") or key in {"system.name", "hostname"}:
            candidates.append(value)
    candidate_norms = [norm(candidate) for candidate in candidates if candidate]
    candidate_shorts = [host_short(candidate) for candidate in candidates if candidate]

    if (
        name_norm in candidate_norms
        or host_norm in candidate_norms
        or name_short in candidate_shorts
        or host_short_name in candidate_shorts
    ):
        if port not in matched:
            matched.append(port)

if not matched and switch_count == "1":
    matched = split_ports(discovered)

print(" ".join(matched))
PY
}

function write_switch_fix_yaml()
{
  local name=${1}
  local host=${2}
  local explicit_ports=${3}
  local discovered_ports=${4}
  local ports
  local port
  local l2_file
  local l3_file
  local generated=()
  local gateway_records
  local gateway_record
  local gateway_ip=""
  local gateway_endpoint=""
  local gateway_pod=""
  local gateway_node=""
  local gateway_pod_ip=""

  ports=$(select_switch_fix_ports "${name}" "${host}" "${explicit_ports}" "${discovered_ports}" "${#SWITCH_CFG_HOSTS[@]}")
  ports=$(normalize_port_list "${ports}")

  if [ -z "${ports}" ]; then
    return
  fi

  gateway_records="${REPORT_DIR}/switch-$(safe_file_component "${name}")-l3-gateways.tsv"
  select_switch_l3_gateways "${name}" "${host}" "${#SWITCH_CFG_HOSTS[@]}" "${explicit_ports}" > "${gateway_records}"

  for port in ${ports}; do
    l2_file="${REPORT_DIR}/switch-$(safe_file_component "${name}")-$(safe_file_component "${port}")-vlan0-L2.yaml"
    l3_file="${REPORT_DIR}/switch-$(safe_file_component "${name}")-$(safe_file_component "${port}")-L3.yaml"
    gateway_ip=""
    gateway_endpoint=""
    gateway_pod=""
    gateway_node=""
    gateway_pod_ip=""
    gateway_record=$(l3_gateway_for_port "${port}" "${gateway_records}")
    if [ -n "${gateway_record}" ]; then
      IFS=$'\t' read -r _gateway_port gateway_ip gateway_endpoint gateway_pod gateway_node gateway_pod_ip <<< "${gateway_record}"
    fi
    {
      echo "# Generated by ${0##*/} on $(date -Is)"
      echo "# Switch: ${name} (${host})"
      echo "# Port: ${port}"
      echo "# Purpose: proposed NVUE patch for SriovNetwork vlan: 0, which sends untagged frames."
      echo "# Review before applying. This script does not apply switch changes."
      echo "# Apply flow on the switch:"
      echo "#   sudo nv config patch /absolute/path/$(basename "${l2_file}")"
      echo "#   sudo nv config diff"
      echo "#   sudo nv config apply"
      echo "#"
      echo "# Assumption: untagged pod traffic should land in access/native VLAN ${SWITCH_L2_VLAN}"
      echo "# on bridge domain ${SWITCH_BRIDGE_DOMAIN}. Override with switch_defaults.native_vlan"
      echo "# or SWITCH_L2_VLAN if this fabric uses a different native VLAN."
      echo "#"
      echo "# If ${port} is currently routed or assigned to a VRF, remove that"
      echo "# routed interface config after review before applying this L2 bridge patch."
      echo "- set:"
      echo "    bridge:"
      echo "      domain:"
      echo "        ${SWITCH_BRIDGE_DOMAIN}:"
      echo "          vlan:"
      echo "            '${SWITCH_L2_VLAN}': {}"
      echo "    interface:"
      echo "      ${port}:"
      echo "        type: swp"
      echo "        bridge:"
      echo "          domain:"
      echo "            ${SWITCH_BRIDGE_DOMAIN}:"
      echo "              access: ${SWITCH_L2_VLAN}"
      echo "              stp:"
      echo "                admin-edge: on"
    } > "${l2_file}"
    generated+=( "${l2_file}" )

    {
      echo "# Generated by ${0##*/} on $(date -Is)"
      echo "# Switch: ${name} (${host})"
      echo "# Port: ${port}"
      echo "# Purpose: proposed NVUE patch to keep or restore ${port} as an L3 routed port."
      echo "# Review before applying. This script does not apply switch changes."
      echo "# Apply flow on the switch:"
      echo "#   sudo nv config patch /absolute/path/$(basename "${l3_file}")"
      echo "#   sudo nv config diff"
      echo "#   sudo nv config apply"
      echo "#"
      echo "# This companion file removes the vlan0 L2 bridge binding from ${port}."
      if is_true "${SWITCH_L3_GATEWAYS:-false}"; then
        if [ -n "${gateway_ip}" ]; then
          echo "# L3 gateway generation: enabled"
          echo "# Endpoint: ${gateway_endpoint} ${gateway_node}/${gateway_pod} ${IFACE} pod IP ${gateway_pod_ip}"
          echo "# Computed gateway: ${gateway_ip} from prefix ${SWITCH_L3_PREFIX} gateway index ${SWITCH_L3_GATEWAY_INDEX}"
          if [ -n "${SWITCH_L3_VRF:-}" ]; then
            echo "# VRF: ${SWITCH_L3_VRF}"
          else
            echo "# VRF: not set by this file. Set SWITCH_L3_VRF or switch_defaults.l3_vrf if needed."
          fi
        else
          echo "# L3 gateway generation: enabled, but no gateway was computed for ${port}."
          echo "# Check that SWITCH_L3_PREFIX is set and this switch name/host matches LLDP chassis data."
        fi
      else
        echo "# It intentionally does not invent IP addresses or VRF membership."
        echo "# If the port needs a specific L3 VRF/IP, copy those settings from"
        echo "# switch-$(safe_file_component "${name}").yaml or the current switch source of truth."
      fi
      echo "- unset:"
      echo "    interface:"
      echo "      ${port}:"
      echo "        bridge:"
      echo "          domain:"
      echo "            ${SWITCH_BRIDGE_DOMAIN}: {}"
      echo "- set:"
      echo "    interface:"
      echo "      ${port}:"
      echo "        type: swp"
      if [ -n "${gateway_ip}" ] || [ -n "${SWITCH_L3_VRF:-}" ]; then
        echo "        ip:"
        if [ -n "${SWITCH_L3_VRF:-}" ]; then
          echo "          vrf: ${SWITCH_L3_VRF}"
        fi
        if [ -n "${gateway_ip}" ]; then
          echo "          address:"
          echo "            ${gateway_ip}: {}"
        fi
      fi
    } > "${l3_file}"
    generated+=( "${l3_file}" )
  done

  printf '%s\n' "${generated[@]}"
}

function capture_switch_settings()
{
  local name=${1}
  local target=${2}
  local password=${3}
  local password_env=${4}
  local output_file=${5}
  shift 5
  local ssh_cmd=( "$@" )
  local password_value="${password}"

  {
    echo "---"
    echo "switch:"
    echo "  name: $(yaml_quote "${name}")"
    echo "  target: $(yaml_quote "${target}")"
    echo "  collected: $(yaml_quote "$(date -Is)")"
  } > "${output_file}"

  if [ -z "${password_value}" ] && [ -n "${password_env}" ]; then
    password_value="${!password_env-}"
  fi

  if [ -n "${password}" ] || [ -n "${password_env}" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      {
        echo "collection_error: $(yaml_quote "password/password_env is configured, but sshpass is not installed")"
      } >> "${output_file}"
      return
    fi
    if [ -z "${password_value}" ] && [ -n "${password_env}" ]; then
      {
        echo "collection_error: $(yaml_quote "password_env=${password_env} is configured, but the environment variable is empty")"
      } >> "${output_file}"
      return
    fi
    SSHPASS="${password_value}" sshpass -e "${ssh_cmd[@]}" "${target}" "bash -s" <<'REMOTE' >> "${output_file}" 2>&1 || true
set +e

function yaml_block()
{
  local key=${1}
  local cmd=${2}
  local rc
  echo "  ${key}:"
  echo "    command: |"
  printf '%s\n' "${cmd}" | sed 's/^/      /'
  echo "    output: |"
  bash -lc "${cmd}" 2>&1 | sed 's/^/      /'
  rc=${PIPESTATUS[0]}
  echo "    exit_code: ${rc}"
}

echo "remote:"
echo "  hostname: '$(hostname)'"
echo "commands:"
yaml_block nv_config_show "nv config show -o yaml 2>/dev/null || nv config show --output yaml 2>/dev/null || nv config show 2>&1 || true"
yaml_block nv_show_interface "nv show interface 2>&1 || true"
yaml_block nv_show_bridge_domain "nv show bridge domain 2>&1 || true"
yaml_block nv_show_vrf "nv show vrf 2>&1 || true"
yaml_block nv_show_router_bgp "nv show router bgp 2>&1 || true"
yaml_block ip_link_detail "ip -d link show 2>&1 || true"
yaml_block ip_addr "ip addr show 2>&1 || true"
yaml_block ip_route_all "ip route show table all 2>&1 || true"
yaml_block bridge_vlan "bridge vlan show 2>&1 || true"
yaml_block bridge_link "bridge link show 2>&1 || true"
yaml_block bridge_fdb "bridge fdb show 2>&1 || true"
yaml_block frr_running_config "if command -v vtysh >/dev/null 2>&1; then vtysh -c 'show running-config'; else echo 'vtysh not found'; fi"
yaml_block frr_bgp_summary "if command -v vtysh >/dev/null 2>&1; then vtysh -c 'show bgp summary'; else echo 'vtysh not found'; fi"
yaml_block frr_evpn_summary "if command -v vtysh >/dev/null 2>&1; then vtysh -c 'show bgp l2vpn evpn summary'; else echo 'vtysh not found'; fi"
yaml_block etc_network_interfaces "if [ -r /etc/network/interfaces ]; then cat /etc/network/interfaces; else echo '/etc/network/interfaces not readable'; fi"
yaml_block etc_frr_conf "if [ -r /etc/frr/frr.conf ]; then cat /etc/frr/frr.conf; else echo '/etc/frr/frr.conf not readable'; fi"
REMOTE
  else
    "${ssh_cmd[@]}" "${target}" "bash -s" <<'REMOTE' >> "${output_file}" 2>&1 || true
set +e

function yaml_block()
{
  local key=${1}
  local cmd=${2}
  local rc
  echo "  ${key}:"
  echo "    command: |"
  printf '%s\n' "${cmd}" | sed 's/^/      /'
  echo "    output: |"
  bash -lc "${cmd}" 2>&1 | sed 's/^/      /'
  rc=${PIPESTATUS[0]}
  echo "    exit_code: ${rc}"
}

echo "remote:"
echo "  hostname: '$(hostname)'"
echo "commands:"
yaml_block nv_config_show "nv config show -o yaml 2>/dev/null || nv config show --output yaml 2>/dev/null || nv config show 2>&1 || true"
yaml_block nv_show_interface "nv show interface 2>&1 || true"
yaml_block nv_show_bridge_domain "nv show bridge domain 2>&1 || true"
yaml_block nv_show_vrf "nv show vrf 2>&1 || true"
yaml_block nv_show_router_bgp "nv show router bgp 2>&1 || true"
yaml_block ip_link_detail "ip -d link show 2>&1 || true"
yaml_block ip_addr "ip addr show 2>&1 || true"
yaml_block ip_route_all "ip route show table all 2>&1 || true"
yaml_block bridge_vlan "bridge vlan show 2>&1 || true"
yaml_block bridge_link "bridge link show 2>&1 || true"
yaml_block bridge_fdb "bridge fdb show 2>&1 || true"
yaml_block frr_running_config "if command -v vtysh >/dev/null 2>&1; then vtysh -c 'show running-config'; else echo 'vtysh not found'; fi"
yaml_block frr_bgp_summary "if command -v vtysh >/dev/null 2>&1; then vtysh -c 'show bgp summary'; else echo 'vtysh not found'; fi"
yaml_block frr_evpn_summary "if command -v vtysh >/dev/null 2>&1; then vtysh -c 'show bgp l2vpn evpn summary'; else echo 'vtysh not found'; fi"
yaml_block etc_network_interfaces "if [ -r /etc/network/interfaces ]; then cat /etc/network/interfaces; else echo '/etc/network/interfaces not readable'; fi"
yaml_block etc_frr_conf "if [ -r /etc/frr/frr.conf ]; then cat /etc/frr/frr.conf; else echo '/etc/frr/frr.conf not readable'; fi"
REMOTE
  fi
}

function resolve_node_ssh_target()
{
  local node=${1}
  local target

  target=$(${K8CL} get node "${node}" \
    -o jsonpath='{range .status.addresses[?(@.type=="InternalIP")]}{.address}{"\n"}{end}' \
    2>/dev/null | awk 'NF { print; exit }')

  if [ -z "${target}" ]; then
    target=$(${K8CL} get nodes -o wide --no-headers 2>/dev/null | \
      awk -v node="${node}" '$1 == node { print $6; exit }')
  fi

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

function ssh_worker()
{
  local target=${1}
  shift
  local ssh_cmd=(ssh)

  if [ -n "${SSH_OPTS:-}" ]; then
    # shellcheck disable=SC2206
    ssh_cmd+=( ${SSH_OPTS} )
  fi
  if [ -n "${WORKER_SSH_OPTS:-}" ]; then
    # shellcheck disable=SC2206
    ssh_cmd+=( ${WORKER_SSH_OPTS} )
  fi
  if [ -n "${WORKER_SSH_PORT:-}" ]; then
    ssh_cmd+=( -p "${WORKER_SSH_PORT}" )
  fi
  if [ -n "${WORKER_SSH_IDENTITY_FILE:-}" ]; then
    ssh_cmd+=( -i "$(expand_local_path "${WORKER_SSH_IDENTITY_FILE}")" )
  fi

  if [ -n "${WORKER_SSH_PASSWORD:-}" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
      echo "ERROR: worker_ssh.password is configured, but sshpass is not installed" >&2
      return 127
    fi
    SSHPASS="${WORKER_SSH_PASSWORD}" sshpass -e "${ssh_cmd[@]}" "${target}" "$@"
  else
    "${ssh_cmd[@]}" "${target}" "$@"
  fi
}

function remote_collect_host()
{
  local label=${1}
  local node=${2}
  local ssh_target=${3}
  local pci=${4}
  local mac=${5}
  local file=${6}

  {
    echo "### ${label} host collection"
    echo "node: ${node}"
    echo "ssh target: ${ssh_target}"
    echo "pod pci: ${pci}"
    echo "pod mac: ${mac}"
    echo "# $(date -Is)"
    ssh_worker "${ssh_target}" "PCI='${pci}' MAC='${mac}' bash -s" <<'REMOTE'
set +e
echo "hostname: $(hostname)"
echo "pci: ${PCI}"
echo "expected-mac: ${MAC}"
echo

if [ ! -e "/sys/bus/pci/devices/${PCI}" ]; then
  echo "ERROR: /sys/bus/pci/devices/${PCI} not found"
  exit 0
fi

PF=$(basename "$(readlink -f "/sys/bus/pci/devices/${PCI}/physfn" 2>/dev/null)")
echo "physfn: ${PF}"
echo "vf-driver:"
basename "$(readlink -f "/sys/bus/pci/devices/${PCI}/driver" 2>/dev/null)"
echo "pf-driver:"
basename "$(readlink -f "/sys/bus/pci/devices/${PF}/driver" 2>/dev/null)"
echo

PF_RDMA_DEVS=()
echo "pf-rdma-devices:"
for RDMA_PATH in /sys/bus/pci/devices/${PF}/infiniband/*; do
  [ -e "${RDMA_PATH}" ] || continue
  RDMA_DEV=$(basename "${RDMA_PATH}")
  PF_RDMA_DEVS+=( "${RDMA_DEV}" )
  echo "${RDMA_DEV}"
done
echo

run_mlxlink_probe() {
  local dev="$1"
  local ran=0

  echo "mlxlink probe for ${dev}:"
  echo "$ mlxlink -d ${dev}"
  if mlxlink -d "${dev}" 2>&1; then
    ran=1
  else
    echo "$ mlxlink -d ${dev} -p 1"
    mlxlink -d "${dev}" -p 1 2>&1 || true
    ran=1
  fi

  if [ "${ran}" -eq 0 ]; then
    echo "mlxlink probe did not run for ${dev}"
  fi
}

echo "mlxlink PF link state:"
if command -v mlxlink >/dev/null 2>&1; then
  if [ ${#PF_RDMA_DEVS[@]} -gt 0 ]; then
    for MLXDEV in "${PF_RDMA_DEVS[@]}"; do
      run_mlxlink_probe "${MLXDEV}"
      echo
    done
  else
    run_mlxlink_probe "${PF}"
  fi
else
  echo "mlxlink not found"
fi
echo

echo "virtfn-map:"
MATCH_VF=""
for V in /sys/bus/pci/devices/${PF}/virtfn*; do
  [ -e "${V}" ] || continue
  TARGET=$(basename "$(readlink -f "${V}")")
  IDX=${V##*virtfn}
  echo "vf ${IDX} -> ${TARGET}"
  if [ "${TARGET}" = "${PCI}" ]; then
    MATCH_VF=${IDX}
  fi
done
echo "matching-vf-index: ${MATCH_VF}"
echo

for NETPATH in /sys/bus/pci/devices/${PF}/net/*; do
  [ -e "${NETPATH}" ] || continue
  IFACE=$(basename "${NETPATH}")
  echo "==== PF ${IFACE} ===="
  ip -d link show "${IFACE}"
  echo
  echo "vf lines:"
  ip -d link show "${IFACE}" | grep -i "vf " || true
  echo
  echo "ethtool:"
  ethtool "${IFACE}" 2>/dev/null || true
  echo
  echo "selected ethtool stats:"
  ethtool -S "${IFACE}" 2>/dev/null | egrep -i 'rx|tx|drop|err|disc|crc|pause|pfc|prio|vf|vport|representor|discard' | head -400 || true
  echo
  echo "mlnx_qos:"
  mlnx_qos -i "${IFACE}" 2>/dev/null || true
  echo
  echo "lldpcli neighbor for ${IFACE}:"
  if command -v lldpcli >/dev/null 2>&1; then
    lldpcli show neighbors ports "${IFACE}" details 2>/dev/null || \
      lldpcli show neighbors ports "${IFACE}" 2>/dev/null || true
    echo
    echo "lldpcli keyvalue for ${IFACE}:"
    lldpcli -f keyvalue show neighbors ports "${IFACE}" details 2>/dev/null || \
      lldpcli -f keyvalue show neighbors ports "${IFACE}" 2>/dev/null || true
    echo
    echo "lldpcli json for ${IFACE}:"
    lldpcli -f json show neighbors ports "${IFACE}" details 2>/dev/null || \
      lldpcli -f json show neighbors ports "${IFACE}" 2>/dev/null || true
  else
    echo "lldpcli not found"
  fi
  echo
  echo "lldpctl fallback for ${IFACE}:"
  lldpctl "${IFACE}" 2>/dev/null || lldpctl 2>/dev/null || true
done

echo
echo "devlink ports:"
devlink port show 2>/dev/null | egrep -i "${PCI}|${PF}|${MAC}" || devlink port show 2>/dev/null || true
echo
echo "lspci vf:"
lspci -s "${PCI}" -vv 2>/dev/null || true
echo
echo "lspci pf:"
lspci -s "${PF}" -vv 2>/dev/null || true
echo
echo "recent mlx5 dmesg:"
dmesg -T 2>/dev/null | egrep -i 'mlx5|sriov|vf|representor' | tail -80 || true
REMOTE
  } > "${file}" 2>&1 || true
}

function remote_ethtool_stats()
{
  local label=${1}
  local node=${2}
  local ssh_target=${3}
  local pci=${4}
  local file=${5}

  {
    echo "### ${label} counters $(date -Is)"
    echo "node: ${node}"
    echo "ssh target: ${ssh_target}"
    ssh_worker "${ssh_target}" "PCI='${pci}' bash -s" <<'REMOTE'
set +e
PF=$(basename "$(readlink -f "/sys/bus/pci/devices/${PCI}/physfn" 2>/dev/null)")
for NETPATH in /sys/bus/pci/devices/${PF}/net/*; do
  [ -e "${NETPATH}" ] || continue
  IFACE=$(basename "${NETPATH}")
  echo "==== ${IFACE} ===="
  ethtool -S "${IFACE}" 2>/dev/null | egrep -i 'rx|tx|drop|err|disc|crc|pause|pfc|prio|vf|vport|discard' | head -400 || true
done
REMOTE
  } >> "${file}" 2>&1 || true
}

function extract_lldp_switch_ports()
{
  local file

  for file in "$@"; do
    [ -r "${file}" ] || continue
    awk -F= '/\.port\.ifname=/ { print $2 }' "${file}"
  done | awk 'NF && !seen[$0]++ { print }' | xargs 2>/dev/null || true
}

function collect_sriov_operator_state()
{
  local file=${1}

  run_log "network operator sriov pods" "${file}" \
    bash -c "${K8CL} -n ${NETOP_NAMESPACE} get pods -o wide | egrep 'sriov-network-config-daemon|sriov-device-plugin|network-operator' || true"
  run_log "sriovnetworknodestates" "${file}" \
    "${K8CL}" -n "${NETOP_NAMESPACE}" get sriovnetworknodestates
  run_log "source sriovnetworknodestate yaml" "${file}" \
    "${K8CL}" -n "${NETOP_NAMESPACE}" get sriovnetworknodestate "${SRC_NODE}" -o yaml
  run_log "dest sriovnetworknodestate yaml" "${file}" \
    "${K8CL}" -n "${NETOP_NAMESPACE}" get sriovnetworknodestate "${DST_NODE}" -o yaml
  run_log "sriovnetworknodepolicies" "${file}" \
    "${K8CL}" -n "${NETOP_NAMESPACE}" get sriovnetworknodepolicies -o wide
  run_log "device plugin config" "${file}" \
    "${K8CL}" -n "${NETOP_NAMESPACE}" get cm device-plugin-config -o yaml
}

function collect_node_operand_logs()
{
  local label=${1}
  local node=${2}
  local file=${3}
  local pods
  local pod

  {
    echo
    echo "### ${label}: sriov-network-config-daemon logs for ${node}"
    echo "# $(date -Is)"
  } >> "${file}"
  pods=$(${K8CL} -n "${NETOP_NAMESPACE}" get pod -l app=sriov-network-config-daemon \
    --field-selector "spec.nodeName=${node}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  for pod in ${pods}; do
    {
      echo
      echo "#### pod/${pod}"
      ${K8CL} -n "${NETOP_NAMESPACE}" logs "${pod}" --tail=300
    } >> "${file}" 2>&1 || true
  done

  {
    echo
    echo "### ${label}: sriov-device-plugin logs for ${node}"
    echo "# $(date -Is)"
  } >> "${file}"
  pods=$(${K8CL} -n "${NETOP_NAMESPACE}" get pod -l app=sriov-device-plugin \
    --field-selector "spec.nodeName=${node}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  for pod in ${pods}; do
    {
      echo
      echo "#### pod/${pod} init"
      ${K8CL} -n "${NETOP_NAMESPACE}" logs "${pod}" -c sriov-device-plugin-init --tail=200
      echo
      echo "#### pod/${pod} init previous"
      ${K8CL} -n "${NETOP_NAMESPACE}" logs "${pod}" -c sriov-device-plugin-init --previous --tail=200
      echo
      echo "#### pod/${pod} device-plugin"
      ${K8CL} -n "${NETOP_NAMESPACE}" logs "${pod}" -c sriov-device-plugin --tail=200
    } >> "${file}" 2>&1 || true
  done
}

function run_switch_checks()
{
  local mac_expr=${1}
  local file=${2}
  local switch_ports=${3:-}
  local ip_expr="${SRC_IP}|${DST_IP}"
  local idx

  load_switch_config

  if [ ${#SWITCH_CFG_HOSTS[@]} -eq 0 ]; then
    return
  fi

  for idx in "${!SWITCH_CFG_HOSTS[@]}"; do
    local name="${SWITCH_CFG_NAMES[${idx}]}"
    local host="${SWITCH_CFG_HOSTS[${idx}]}"
    local user="${SWITCH_CFG_USERS[${idx}]}"
    local port="${SWITCH_CFG_PORTS[${idx}]}"
    local identity="${SWITCH_CFG_IDENTITIES[${idx}]}"
    local password="${SWITCH_CFG_PASSWORDS[${idx}]}"
    local password_env="${SWITCH_CFG_PASSWORD_ENVS[${idx}]}"
    local server_ports="${SWITCH_CFG_SERVER_PORTS[${idx}]:-}"
    local target="${host}"
    local ssh_cmd=(ssh)
    local switch_file="${REPORT_DIR}/switch-$(safe_file_component "${name}").yaml"
    local fix_files

    if [ -n "${SSH_OPTS:-}" ]; then
      # shellcheck disable=SC2206
      ssh_cmd+=( ${SSH_OPTS} )
    fi
    if [ -n "${user}" ] && [[ "${host}" != *@* ]]; then
      target="${user}@${host}"
    fi
    if [ -n "${port}" ]; then
      ssh_cmd+=( -p "${port}" )
    fi
    if [ -n "${identity}" ]; then
      ssh_cmd+=( -i "$(expand_local_path "${identity}")" )
    fi

    capture_switch_settings "${name}" "${target}" "${password}" "${password_env}" "${switch_file}" "${ssh_cmd[@]}"
    fix_files=$(write_switch_fix_yaml "${name}" "${host}" "${server_ports}" "${switch_ports}")

    {
      echo
      echo "### switch ${name} (${target})"
      echo "# $(date -Is)"
      echo "settings snapshot: ${switch_file}"
      if [ -n "${fix_files}" ]; then
        echo "proposed switch config YAML:"
        printf '%s\n' "${fix_files}" | sed 's/^/  /'
      else
        echo "proposed switch config YAML: none generated; no switch ports matched this switch entry"
      fi
      if [ -n "${password}" ] || [ -n "${password_env}" ]; then
        if ! command -v sshpass >/dev/null 2>&1; then
          echo "ERROR: password/password_env is configured, but sshpass is not installed"
          continue
        fi
        local password_value="${password}"
        if [ -z "${password_value}" ] && [ -n "${password_env}" ]; then
          password_value="${!password_env-}"
        fi
        if [ -z "${password_value}" ] && [ -n "${password_env}" ]; then
          echo "ERROR: password_env=${password_env} is configured, but the environment variable is empty"
          continue
        fi
        echo "$ SSHPASS=<redacted> sshpass -e ${ssh_cmd[*]} ${target} ..."
        SSHPASS="${password_value}" sshpass -e "${ssh_cmd[@]}" "${target}" "MAC_EXPR='${mac_expr}' IP_EXPR='${ip_expr}' SWITCH_PORTS='${switch_ports}' bash -s" <<'REMOTE'
set +e
echo "hostname: $(hostname)"
echo "bridge fdb:"
bridge fdb show 2>/dev/null | egrep -i "${MAC_EXPR}" || true
echo
echo "nv mac table:"
nv show bridge domain br_default mac-table 2>/dev/null | egrep -i "${MAC_EXPR}" || true
echo
echo "net show bridge macs:"
net show bridge macs 2>/dev/null | egrep -i "${MAC_EXPR}" || true
echo
echo "lldpcli neighbors:"
lldpcli show neighbors 2>/dev/null || true
echo
echo "lldpctl fallback:"
lldpctl 2>/dev/null || true
echo
echo "VLAN/bridge membership for LLDP-discovered server ports:"
if [ -n "${SWITCH_PORTS:-}" ]; then
  for PORT in ${SWITCH_PORTS}; do
    echo
    echo "==== ${PORT} ===="
    echo "ip -d link show ${PORT}:"
    ip -d link show "${PORT}" 2>&1 || true
    echo
    echo "bridge link show dev ${PORT}:"
    bridge link show dev "${PORT}" 2>&1 || true
    echo
    echo "bridge vlan show dev ${PORT}:"
    bridge vlan show dev "${PORT}" 2>&1 || true
    echo
    echo "bridge fdb show dev ${PORT} matching pod MACs:"
    bridge fdb show dev "${PORT}" 2>/dev/null | egrep -i "${MAC_EXPR}" || true
    echo
    echo "nv show interface ${PORT}:"
    nv show interface "${PORT}" 2>&1 || true
    echo
    echo "nv show bridge domain br_default port ${PORT}:"
    nv show bridge domain br_default port "${PORT}" 2>&1 || true
    echo
    echo "net show interface ${PORT}:"
    net show interface "${PORT}" 2>&1 || true
  done
else
  echo "No LLDP switch ports were discovered from source-host.txt/dest-host.txt"
fi
echo
echo "all bridge VLAN membership:"
bridge vlan show 2>/dev/null || true
echo
echo "nv bridge domain summary:"
nv show bridge domain 2>/dev/null || true
echo
echo "FRR/BGP state:"
if command -v vtysh >/dev/null 2>&1; then
  echo "show bgp summary:"
  vtysh -c 'show bgp summary' 2>/dev/null || true
  echo
  echo "show bgp l2vpn evpn summary:"
  vtysh -c 'show bgp l2vpn evpn summary' 2>/dev/null || true
  echo
  echo "show evpn vni:"
  vtysh -c 'show evpn vni' 2>/dev/null || true
  echo
  echo "show evpn mac vni all matching pod MACs:"
  vtysh -c 'show evpn mac vni all' 2>/dev/null | egrep -i "${MAC_EXPR}" || true
  echo
  echo "show bgp l2vpn evpn route matching pod MACs/IPs:"
  vtysh -c 'show bgp l2vpn evpn route' 2>/dev/null | egrep -i "${MAC_EXPR}|${IP_EXPR}" || true
  echo
  echo "show ip route matching pod IPs:"
  vtysh -c 'show ip route' 2>/dev/null | egrep -i "${IP_EXPR}" || true
else
  echo "vtysh not found"
fi
echo
echo "Cumulus/NVIDIA BGP helpers:"
net show bgp summary 2>/dev/null || true
echo
nv show vrf default router bgp 2>/dev/null || true
REMOTE
      else
        echo "$ ${ssh_cmd[*]} ${target} ..."
        "${ssh_cmd[@]}" "${target}" "MAC_EXPR='${mac_expr}' IP_EXPR='${ip_expr}' SWITCH_PORTS='${switch_ports}' bash -s" <<'REMOTE'
set +e
echo "hostname: $(hostname)"
echo "bridge fdb:"
bridge fdb show 2>/dev/null | egrep -i "${MAC_EXPR}" || true
echo
echo "nv mac table:"
nv show bridge domain br_default mac-table 2>/dev/null | egrep -i "${MAC_EXPR}" || true
echo
echo "net show bridge macs:"
net show bridge macs 2>/dev/null | egrep -i "${MAC_EXPR}" || true
echo
echo "lldpcli neighbors:"
lldpcli show neighbors 2>/dev/null || true
echo
echo "lldpctl fallback:"
lldpctl 2>/dev/null || true
echo
echo "VLAN/bridge membership for LLDP-discovered server ports:"
if [ -n "${SWITCH_PORTS:-}" ]; then
  for PORT in ${SWITCH_PORTS}; do
    echo
    echo "==== ${PORT} ===="
    echo "ip -d link show ${PORT}:"
    ip -d link show "${PORT}" 2>&1 || true
    echo
    echo "bridge link show dev ${PORT}:"
    bridge link show dev "${PORT}" 2>&1 || true
    echo
    echo "bridge vlan show dev ${PORT}:"
    bridge vlan show dev "${PORT}" 2>&1 || true
    echo
    echo "bridge fdb show dev ${PORT} matching pod MACs:"
    bridge fdb show dev "${PORT}" 2>/dev/null | egrep -i "${MAC_EXPR}" || true
    echo
    echo "nv show interface ${PORT}:"
    nv show interface "${PORT}" 2>&1 || true
    echo
    echo "nv show bridge domain br_default port ${PORT}:"
    nv show bridge domain br_default port "${PORT}" 2>&1 || true
    echo
    echo "net show interface ${PORT}:"
    net show interface "${PORT}" 2>&1 || true
  done
else
  echo "No LLDP switch ports were discovered from source-host.txt/dest-host.txt"
fi
echo
echo "all bridge VLAN membership:"
bridge vlan show 2>/dev/null || true
echo
echo "nv bridge domain summary:"
nv show bridge domain 2>/dev/null || true
echo
echo "FRR/BGP state:"
if command -v vtysh >/dev/null 2>&1; then
  echo "show bgp summary:"
  vtysh -c 'show bgp summary' 2>/dev/null || true
  echo
  echo "show bgp l2vpn evpn summary:"
  vtysh -c 'show bgp l2vpn evpn summary' 2>/dev/null || true
  echo
  echo "show evpn vni:"
  vtysh -c 'show evpn vni' 2>/dev/null || true
  echo
  echo "show evpn mac vni all matching pod MACs:"
  vtysh -c 'show evpn mac vni all' 2>/dev/null | egrep -i "${MAC_EXPR}" || true
  echo
  echo "show bgp l2vpn evpn route matching pod MACs/IPs:"
  vtysh -c 'show bgp l2vpn evpn route' 2>/dev/null | egrep -i "${MAC_EXPR}|${IP_EXPR}" || true
  echo
  echo "show ip route matching pod IPs:"
  vtysh -c 'show ip route' 2>/dev/null | egrep -i "${IP_EXPR}" || true
else
  echo "vtysh not found"
fi
echo
echo "Cumulus/NVIDIA BGP helpers:"
net show bgp summary 2>/dev/null || true
echo
nv show vrf default router bgp 2>/dev/null || true
REMOTE
      fi
    } >> "${file}" 2>&1 || true
  done
}

load_switch_config

SRC_NODE=$(pod_jsonpath "${SRC_POD}" '{.spec.nodeName}')
DST_NODE=$(pod_jsonpath "${DST_POD}" '{.spec.nodeName}')
SRC_SSH_TARGET=$(resolve_node_ssh_target "${SRC_NODE}")
DST_SSH_TARGET=$(resolve_node_ssh_target "${DST_NODE}")

get_network_status "${SRC_POD}" "${REPORT_DIR}/src-network-status.json"
get_network_status "${DST_POD}" "${REPORT_DIR}/dst-network-status.json"

SRC_EP=$(parse_endpoint "${REPORT_DIR}/src-network-status.json")
DST_EP=$(parse_endpoint "${REPORT_DIR}/dst-network-status.json")

if [ -z "${SRC_EP}" ] || [ -z "${DST_EP}" ]; then
  echo "Unable to find interface ${IFACE} in both pod network-status annotations." >&2
  echo "See ${REPORT_DIR}/src-network-status.json and ${REPORT_DIR}/dst-network-status.json" >&2
  exit 2
fi

IFS=$'\t' read -r SRC_NETWORK SRC_IFACE SRC_IP SRC_MAC SRC_PCI SRC_RDMA <<< "${SRC_EP}"
IFS=$'\t' read -r DST_NETWORK DST_IFACE DST_IP DST_MAC DST_PCI DST_RDMA <<< "${DST_EP}"

NAD_NS=${SRC_NETWORK%%/*}
NAD_NAME=${SRC_NETWORK##*/}
if [ "${NAD_NS}" = "${SRC_NETWORK}" ]; then
  NAD_NS=${NS}
fi

{
  echo "SR-IOV fabric debug report"
  echo "time: $(date -Is)"
  echo "report dir: ${REPORT_DIR}"
  echo
  echo "source pod: ${SRC_POD}"
  echo "source node: ${SRC_NODE}"
  echo "source ssh target: ${SRC_SSH_TARGET}"
  echo "source iface/ip/mac/pci/rdma: ${SRC_IFACE} ${SRC_IP} ${SRC_MAC} ${SRC_PCI} ${SRC_RDMA}"
  echo "source network: ${SRC_NETWORK}"
  echo
  echo "dest pod: ${DST_POD}"
  echo "dest node: ${DST_NODE}"
  echo "dest ssh target: ${DST_SSH_TARGET}"
  echo "dest iface/ip/mac/pci/rdma: ${DST_IFACE} ${DST_IP} ${DST_MAC} ${DST_PCI} ${DST_RDMA}"
  echo "dest network: ${DST_NETWORK}"
  echo
  echo "NAD: ${NAD_NS}/${NAD_NAME}"
  echo "SriovNetwork guess: ${NETOP_NAMESPACE}/${NAD_NAME}"
  echo
  echo "Switch checks:"
  echo "- Pod RDMA and verbs state is collected in pod-rdma.txt with rdma link, ibv_devices, ibv_devinfo, ibv_info, show_gids, and sysfs GUID/GID checks when present."
  echo "- SR-IOV node state, node policies, device-plugin config, and operand logs are collected in sriov-operator-state.txt."
  echo "- LLDP neighbor data is collected from each mapped host PF with lldpcli."
  echo "- Check source-host.txt and dest-host.txt for 'lldpcli neighbor for <PF>'."
  echo "- mlxlink PF link state is collected from the PF RDMA device in source-host.txt and dest-host.txt."
  echo "- Optional switch logins come from ${SWITCH_CONFIG} and/or SWITCH_HOSTS."
  echo "- Current switch settings are collected as switch-<name>.yaml for every configured switch login."
  echo "- Proposed per-port NVUE L2 patch files are generated as switch-<name>-<port>-vlan0-L2.yaml."
  echo "- Companion L3 restore patches are generated as switch-<name>-<port>-L3.yaml."
  echo "- Set SWITCH_L3_GATEWAYS=true plus SWITCH_L3_PREFIX/NETOP_PER_NODE_PREFIX to include computed gateway IPs in L3 patches."
  echo "- Switch VLAN/bridge membership is collected for LLDP-discovered switch ports."
  echo "- Confirm both ports are in the same L2 domain for VLAN used by the SriovNetwork."
  echo "- Current NAD/SriovNetwork YAML below shows whether CNI sends untagged vlan 0 or a VLAN tag."
  echo "- Check switch MAC table for:"
  echo "  source MAC ${SRC_MAC}"
  echo "  dest MAC   ${DST_MAC}"
  echo "- If the switch uses EVPN/VXLAN, FRR/BGP EVPN output should show healthy peers and MAC/IP routes."
  echo "- If this is a simple bridged VLAN, FRR is secondary; bridge FDB and VLAN membership are authoritative."
  echo "- If source MAC is absent, egress from ${SRC_NODE}/${SRC_PCI} is not reaching the switch."
  echo "- If source and dest MACs are learned on different VLANs, fix VLAN/SriovNetwork config."
} > "${SUMMARY}"

run_log "source pod wide" "${REPORT_DIR}/pods.txt" \
  "${K8CL}" -n "${NS}" get pod "${SRC_POD}" -o wide
run_log "dest pod wide" "${REPORT_DIR}/pods.txt" \
  "${K8CL}" -n "${NS}" get pod "${DST_POD}" -o wide
pod_exec_log "${SRC_POD}" "${SRC_IFACE} rdma state" "${REPORT_DIR}/pod-rdma.txt" \
  "$(pod_rdma_cmd "${SRC_IFACE}" "${SRC_RDMA}")"
pod_exec_log "${DST_POD}" "${DST_IFACE} rdma state" "${REPORT_DIR}/pod-rdma.txt" \
  "$(pod_rdma_cmd "${DST_IFACE}" "${DST_RDMA}")"
run_log "NAD yaml" "${REPORT_DIR}/network.yaml" \
  "${K8CL}" -n "${NAD_NS}" get network-attachment-definitions "${NAD_NAME}" -o yaml
run_log "SriovNetwork yaml" "${REPORT_DIR}/network.yaml" \
  "${K8CL}" -n "${NETOP_NAMESPACE}" get sriovnetwork "${NAD_NAME}" -o yaml
run_log "nodes wide" "${REPORT_DIR}/nodes.txt" \
  "${K8CL}" get nodes -o wide
run_log "source node describe resources" "${REPORT_DIR}/nodes.txt" \
  "${K8CL}" describe node "${SRC_NODE}"
run_log "dest node describe resources" "${REPORT_DIR}/nodes.txt" \
  "${K8CL}" describe node "${DST_NODE}"
collect_sriov_operator_state "${REPORT_DIR}/sriov-operator-state.txt"
collect_node_operand_logs "source" "${SRC_NODE}" "${REPORT_DIR}/sriov-operator-state.txt"
collect_node_operand_logs "dest" "${DST_NODE}" "${REPORT_DIR}/sriov-operator-state.txt"

remote_collect_host "source" "${SRC_NODE}" "${SRC_SSH_TARGET}" "${SRC_PCI}" "${SRC_MAC}" "${REPORT_DIR}/source-host.txt"
remote_collect_host "dest" "${DST_NODE}" "${DST_SSH_TARGET}" "${DST_PCI}" "${DST_MAC}" "${REPORT_DIR}/dest-host.txt"
SWITCH_PORTS_DISCOVERED=$(extract_lldp_switch_ports "${REPORT_DIR}/source-host.txt" "${REPORT_DIR}/dest-host.txt")
{
  echo
  echo "LLDP-discovered switch ports: ${SWITCH_PORTS_DISCOVERED:-none}"
} >> "${SUMMARY}"

COUNTERS="${REPORT_DIR}/host-counters-around-ping.txt"
remote_ethtool_stats "source before" "${SRC_NODE}" "${SRC_SSH_TARGET}" "${SRC_PCI}" "${COUNTERS}"
remote_ethtool_stats "dest before" "${DST_NODE}" "${DST_SSH_TARGET}" "${DST_PCI}" "${COUNTERS}"

{
  echo
  echo "### pod ping $(date -Is)"
  echo "$ ${K8CL} -n ${NS} exec ${SRC_POD} -- sh -c 'ip neigh del ${DST_IP} dev ${SRC_IFACE} 2>/dev/null || true; ip route get ${DST_IP}; ip route get ${DST_IP} from ${SRC_IP} 2>/dev/null || true; ping -c ${PING_COUNT} -W ${PING_TIMEOUT} -I ${SRC_IFACE} ${DST_IP} || true; ping -c ${PING_COUNT} -W ${PING_TIMEOUT} -I ${SRC_IP} ${DST_IP} || true; ip neigh show dev ${SRC_IFACE}'"
  ${K8CL} -n "${NS}" exec "${SRC_POD}" -- sh -c "ip neigh del ${DST_IP} dev ${SRC_IFACE} 2>/dev/null || true; ip route get ${DST_IP}; ip route get ${DST_IP} from ${SRC_IP} 2>/dev/null || true; echo ping via interface ${SRC_IFACE}; ping -c ${PING_COUNT} -W ${PING_TIMEOUT} -I ${SRC_IFACE} ${DST_IP} || true; echo; echo ping via source IP ${SRC_IP}; ping -c ${PING_COUNT} -W ${PING_TIMEOUT} -I ${SRC_IP} ${DST_IP} || true; ip neigh show dev ${SRC_IFACE}"
} > "${REPORT_DIR}/pod-ping.txt" 2>&1 || true

remote_ethtool_stats "source after" "${SRC_NODE}" "${SRC_SSH_TARGET}" "${SRC_PCI}" "${COUNTERS}"
remote_ethtool_stats "dest after" "${DST_NODE}" "${DST_SSH_TARGET}" "${DST_PCI}" "${COUNTERS}"

MAC_EXPR="$(echo "${SRC_MAC}|${DST_MAC}" | tr '[:upper:]' '[:lower:]')"
run_switch_checks "${MAC_EXPR}" "${REPORT_DIR}/switch-mac-checks.txt" "${SWITCH_PORTS_DISCOVERED}"

cat > "${REPORT_DIR}/switch-checklist.txt" <<EOF
Check these on the switch fabric:

Endpoint:
  NAD/SriovNetwork: ${NAD_NAME}
  source node/pod/interface: ${SRC_NODE}/${SRC_POD}/${SRC_IFACE}
  source IP/MAC/PCI: ${SRC_IP} ${SRC_MAC} ${SRC_PCI}
  dest node/pod/interface: ${DST_NODE}/${DST_POD}/${DST_IFACE}
  dest IP/MAC/PCI: ${DST_IP} ${DST_MAC} ${DST_PCI}

MAC table:
  ${SRC_MAC}
  ${DST_MAC}

Questions:
  0. In pod-rdma.txt, does rdma link show the pod netdev mapped to the expected RDMA device?
  1. In source-host.txt, what switch chassis/port does lldpcli show for the source PF?
  2. In dest-host.txt, what switch chassis/port does lldpcli show for the destination PF?
  3. In source-host.txt and dest-host.txt, does mlxlink report link up, expected speed, and healthy FEC?
  4. Are both server ports connected to the expected switch ports?
  5. Are both switch ports in the same L2 domain?
  6. If the ports are trunks, does the SriovNetwork VLAN match the allowed/native VLAN?
  7. If SriovNetwork has vlan: 0, are both ports using the same untagged/native VLAN?
  8. Does the switch learn source MAC ${SRC_MAC} when the ping runs?
  9. Does it learn destination MAC ${DST_MAC} on the peer port?
  10. If this VLAN is stretched with EVPN, are FRR EVPN BGP peers established?
  11. If this VLAN is stretched with EVPN, does FRR show EVPN MAC/IP routes for ${SRC_MAC} and ${DST_MAC}?
  12. In switch-mac-checks.txt, do the LLDP-discovered ports (${SWITCH_PORTS_DISCOVERED:-none}) have matching bridge/VLAN membership?

Common Cumulus/NVIDIA switch probes:
  bridge fdb show | egrep -i '${SRC_MAC}|${DST_MAC}'
  bridge vlan show dev <lldp-discovered-port>
  bridge link show dev <lldp-discovered-port>
  nv show interface <lldp-discovered-port>
  nv show bridge domain br_default port <lldp-discovered-port>
  nv show bridge domain br_default mac-table | egrep -i '${SRC_MAC}|${DST_MAC}'
  net show bridge macs | egrep -i '${SRC_MAC}|${DST_MAC}'
  lldpcli show neighbors
  mlxlink -d <pf-rdma-device>
  vtysh -c 'show bgp summary'
  vtysh -c 'show bgp l2vpn evpn summary'
  vtysh -c 'show evpn vni'
  vtysh -c 'show evpn mac vni all' | egrep -i '${SRC_MAC}|${DST_MAC}'
  vtysh -c 'show bgp l2vpn evpn route' | egrep -i '${SRC_MAC}|${DST_MAC}|${SRC_IP}|${DST_IP}'

Generated fix artifacts:
  switch-<switchname>-<port>-vlan0-L2.yaml
    Proposed NVUE patch for untagged SriovNetwork vlan: 0 L2 connectivity.
  switch-<switchname>-<port>-L3.yaml
    Companion patch to keep or restore the port as L3. If SWITCH_L3_GATEWAYS=true
    and SWITCH_L3_PREFIX or NETOP_PER_NODE_PREFIX is set, this includes the
    computed gateway IP for the source/destination per-node CIDR on that port.
    Use SWITCH_L3_VRF or switch_defaults.l3_vrf when the port belongs to a VRF.
    Review each file and run nv config diff before applying on a switch.
EOF

echo "Wrote report: ${REPORT_DIR}"
echo "Start with: ${SUMMARY}"
