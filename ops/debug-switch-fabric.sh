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

function usage()
{
  cat <<EOF
usage: $0 SRC_POD DST_POD [namespace] [interface]

Examples:
  $0 test2-05-1 test1-05-1 default net2

Environment:
  K8CL             kubectl command to use. Default: kubectl
  NETOP_NAMESPACE  Network Operator namespace. Default: nvidia-network-operator
  SWITCH_HOSTS     Optional space-separated switch hostnames to query over ssh
  REPORT_DIR       Existing or new output directory. Default: /tmp/netop-switch-fabric-<timestamp>
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

function remote_collect_host()
{
  local label=${1}
  local node=${2}
  local pci=${3}
  local mac=${4}
  local file=${5}

  {
    echo "### ${label} host collection"
    echo "node: ${node}"
    echo "pod pci: ${pci}"
    echo "pod mac: ${mac}"
    echo "# $(date -Is)"
    ssh "${node}" "PCI='${pci}' MAC='${mac}' bash -s" <<'REMOTE'
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
  local pci=${3}
  local file=${4}

  {
    echo "### ${label} counters $(date -Is)"
    ssh "${node}" "PCI='${pci}' bash -s" <<'REMOTE'
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

function run_switch_checks()
{
  local mac_expr=${1}
  local file=${2}

  if [ -z "${SWITCH_HOSTS:-}" ]; then
    return
  fi

  for sw in ${SWITCH_HOSTS}; do
    {
      echo
      echo "### switch ${sw}"
      echo "# $(date -Is)"
      ssh "${sw}" "MAC_EXPR='${mac_expr}' bash -s" <<'REMOTE'
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
REMOTE
    } >> "${file}" 2>&1 || true
  done
}

SRC_NODE=$(pod_jsonpath "${SRC_POD}" '{.spec.nodeName}')
DST_NODE=$(pod_jsonpath "${DST_POD}" '{.spec.nodeName}')

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
  echo "source iface/ip/mac/pci/rdma: ${SRC_IFACE} ${SRC_IP} ${SRC_MAC} ${SRC_PCI} ${SRC_RDMA}"
  echo "source network: ${SRC_NETWORK}"
  echo
  echo "dest pod: ${DST_POD}"
  echo "dest node: ${DST_NODE}"
  echo "dest iface/ip/mac/pci/rdma: ${DST_IFACE} ${DST_IP} ${DST_MAC} ${DST_PCI} ${DST_RDMA}"
  echo "dest network: ${DST_NETWORK}"
  echo
  echo "NAD: ${NAD_NS}/${NAD_NAME}"
  echo "SriovNetwork guess: ${NETOP_NAMESPACE}/${NAD_NAME}"
  echo
  echo "Switch checks:"
  echo "- LLDP neighbor data is collected from each mapped host PF with lldpcli."
  echo "- Check source-host.txt and dest-host.txt for 'lldpcli neighbor for <PF>'."
  echo "- Confirm both ports are in the same L2 domain for VLAN used by the SriovNetwork."
  echo "- Current NAD/SriovNetwork YAML below shows whether CNI sends untagged vlan 0 or a VLAN tag."
  echo "- Check switch MAC table for:"
  echo "  source MAC ${SRC_MAC}"
  echo "  dest MAC   ${DST_MAC}"
  echo "- If source MAC is absent, egress from ${SRC_NODE}/${SRC_PCI} is not reaching the switch."
  echo "- If source and dest MACs are learned on different VLANs, fix VLAN/SriovNetwork config."
} > "${SUMMARY}"

run_log "source pod wide" "${REPORT_DIR}/pods.txt" \
  "${K8CL}" -n "${NS}" get pod "${SRC_POD}" -o wide
run_log "dest pod wide" "${REPORT_DIR}/pods.txt" \
  "${K8CL}" -n "${NS}" get pod "${DST_POD}" -o wide
run_log "NAD yaml" "${REPORT_DIR}/network.yaml" \
  "${K8CL}" -n "${NAD_NS}" get network-attachment-definitions "${NAD_NAME}" -o yaml
run_log "SriovNetwork yaml" "${REPORT_DIR}/network.yaml" \
  "${K8CL}" -n "${NETOP_NAMESPACE}" get sriovnetwork "${NAD_NAME}" -o yaml
run_log "source node describe resources" "${REPORT_DIR}/nodes.txt" \
  "${K8CL}" describe node "${SRC_NODE}"
run_log "dest node describe resources" "${REPORT_DIR}/nodes.txt" \
  "${K8CL}" describe node "${DST_NODE}"

remote_collect_host "source" "${SRC_NODE}" "${SRC_PCI}" "${SRC_MAC}" "${REPORT_DIR}/source-host.txt"
remote_collect_host "dest" "${DST_NODE}" "${DST_PCI}" "${DST_MAC}" "${REPORT_DIR}/dest-host.txt"

COUNTERS="${REPORT_DIR}/host-counters-around-ping.txt"
remote_ethtool_stats "source before" "${SRC_NODE}" "${SRC_PCI}" "${COUNTERS}"
remote_ethtool_stats "dest before" "${DST_NODE}" "${DST_PCI}" "${COUNTERS}"

{
  echo
  echo "### pod ping $(date -Is)"
  echo "$ ${K8CL} -n ${NS} exec ${SRC_POD} -- sh -c 'ip neigh del ${DST_IP} dev ${SRC_IFACE} 2>/dev/null || true; ping -c ${PING_COUNT} -W ${PING_TIMEOUT} -I ${SRC_IFACE} ${DST_IP} || true; ip neigh show dev ${SRC_IFACE}'"
  ${K8CL} -n "${NS}" exec "${SRC_POD}" -- sh -c "ip neigh del ${DST_IP} dev ${SRC_IFACE} 2>/dev/null || true; ping -c ${PING_COUNT} -W ${PING_TIMEOUT} -I ${SRC_IFACE} ${DST_IP} || true; ip neigh show dev ${SRC_IFACE}"
} > "${REPORT_DIR}/pod-ping.txt" 2>&1 || true

remote_ethtool_stats "source after" "${SRC_NODE}" "${SRC_PCI}" "${COUNTERS}"
remote_ethtool_stats "dest after" "${DST_NODE}" "${DST_PCI}" "${COUNTERS}"

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
  1. In source-host.txt, what switch chassis/port does lldpcli show for the source PF?
  2. In dest-host.txt, what switch chassis/port does lldpcli show for the destination PF?
  3. Are both server ports connected to the expected switch ports?
  4. Are both switch ports in the same L2 domain?
  5. If the ports are trunks, does the SriovNetwork VLAN match the allowed/native VLAN?
  6. If SriovNetwork has vlan: 0, are both ports using the same untagged/native VLAN?
  7. Does the switch learn source MAC ${SRC_MAC} when the ping runs?
  8. Does it learn destination MAC ${DST_MAC} on the peer port?

Common Cumulus/NVIDIA switch probes:
  bridge fdb show | egrep -i '${SRC_MAC}|${DST_MAC}'
  nv show bridge domain br_default mac-table | egrep -i '${SRC_MAC}|${DST_MAC}'
  net show bridge macs | egrep -i '${SRC_MAC}|${DST_MAC}'
  lldpcli show neighbors
EOF

echo "Wrote report: ${REPORT_DIR}"
echo "Start with: ${SUMMARY}"
