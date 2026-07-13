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
  DEBUG_CFG_WORKER_SSH_USER=""
  DEBUG_CFG_WORKER_SSH_PORT=""
  DEBUG_CFG_WORKER_SSH_IDENTITY_FILE=""
  DEBUG_CFG_WORKER_SSH_PASSWORD=""
  DEBUG_CFG_WORKER_SSH_OPTS=""

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

            if section == "worker_ssh":
                if re.match(r"^\S", line):
                    section = None
                    continue
                match = key_value.match(stripped)
                if match:
                    worker_ssh[match.group(1)] = clean_value(match.group(2))
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
    return {"worker_ssh": worker_ssh, "switches": switches}

try:
    import yaml  # type: ignore

    with open(path, encoding="utf-8") as stream:
        data = yaml.safe_load(stream) or {}
except Exception:
    data = simple_yaml(path)

worker_ssh = {}
if isinstance(data, dict):
    worker_ssh = data.get("worker_ssh") or {}
    cluster = data.get("cluster") or {}
    if isinstance(cluster, dict) and not worker_ssh:
        worker_ssh = cluster.get("worker_ssh") or {}
if not isinstance(worker_ssh, dict):
    worker_ssh = {}

print(f"DEBUG_CFG_WORKER_SSH_USER={shlex.quote(str(worker_ssh.get('user') or worker_ssh.get('username') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_PORT={shlex.quote(str(worker_ssh.get('port') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_IDENTITY_FILE={shlex.quote(str(worker_ssh.get('identity_file') or worker_ssh.get('identity') or worker_ssh.get('key_file') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_PASSWORD={shlex.quote(str(worker_ssh.get('password') or '').strip())}")
print(f"DEBUG_CFG_WORKER_SSH_OPTS={shlex.quote(str(worker_ssh.get('options') or worker_ssh.get('ssh_opts') or '').strip())}")

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

    print(f"SWITCH_CFG_NAMES+=({shlex.quote(name)})")
    print(f"SWITCH_CFG_HOSTS+=({shlex.quote(host)})")
    print(f"SWITCH_CFG_USERS+=({shlex.quote(user)})")
    print(f"SWITCH_CFG_PORTS+=({shlex.quote(port)})")
    print(f"SWITCH_CFG_IDENTITIES+=({shlex.quote(identity)})")
    print(f"SWITCH_CFG_PASSWORDS+=({shlex.quote(password)})")
    print(f"SWITCH_CFG_PASSWORD_ENVS+=({shlex.quote(password_env)})")
PY
    # shellcheck disable=SC1090
    source "${parsed}"
  fi

  WORKER_SSH_USER=${WORKER_SSH_USER:-${DEBUG_CFG_WORKER_SSH_USER:-}}
  WORKER_SSH_PORT=${WORKER_SSH_PORT:-${DEBUG_CFG_WORKER_SSH_PORT:-}}
  WORKER_SSH_IDENTITY_FILE=${WORKER_SSH_IDENTITY_FILE:-${DEBUG_CFG_WORKER_SSH_IDENTITY_FILE:-}}
  WORKER_SSH_PASSWORD=${WORKER_SSH_PASSWORD:-${DEBUG_CFG_WORKER_SSH_PASSWORD:-}}
  WORKER_SSH_OPTS=${WORKER_SSH_OPTS:-${DEBUG_CFG_WORKER_SSH_OPTS:-}}

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
    local target="${host}"
    local ssh_cmd=(ssh)

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

    {
      echo
      echo "### switch ${name} (${target})"
      echo "# $(date -Is)"
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
        SSHPASS="${password_value}" sshpass -e "${ssh_cmd[@]}" "${target}" "MAC_EXPR='${mac_expr}' IP_EXPR='${ip_expr}' bash -s" <<'REMOTE'
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
        "${ssh_cmd[@]}" "${target}" "MAC_EXPR='${mac_expr}' IP_EXPR='${ip_expr}' bash -s" <<'REMOTE'
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
run_switch_checks "${MAC_EXPR}" "${REPORT_DIR}/switch-mac-checks.txt"

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

Common Cumulus/NVIDIA switch probes:
  bridge fdb show | egrep -i '${SRC_MAC}|${DST_MAC}'
  nv show bridge domain br_default mac-table | egrep -i '${SRC_MAC}|${DST_MAC}'
  net show bridge macs | egrep -i '${SRC_MAC}|${DST_MAC}'
  lldpcli show neighbors
  mlxlink -d <pf-rdma-device>
  vtysh -c 'show bgp summary'
  vtysh -c 'show bgp l2vpn evpn summary'
  vtysh -c 'show evpn vni'
  vtysh -c 'show evpn mac vni all' | egrep -i '${SRC_MAC}|${DST_MAC}'
  vtysh -c 'show bgp l2vpn evpn route' | egrep -i '${SRC_MAC}|${DST_MAC}|${SRC_IP}|${DST_IP}'
EOF

echo "Wrote report: ${REPORT_DIR}"
echo "Start with: ${SUMMARY}"
