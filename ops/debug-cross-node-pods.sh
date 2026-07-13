#!/bin/bash
#
# Collect cross-node SR-IOV pod connectivity evidence.
#
# This script is intentionally read-only. It collects pod network-status,
# interface state, routes, neighbor state, counters, bounded packet captures,
# and ping results for matching secondary interfaces on two pods.
#
set -u

K8CL=${K8CL:-kubectl}
PING_COUNT=${PING_COUNT:-2}
PING_TIMEOUT=${PING_TIMEOUT:-1}
CAPTURE_SECONDS=${CAPTURE_SECONDS:-6}
SKIP_TCPDUMP=${SKIP_TCPDUMP:-0}

function usage()
{
  cat <<EOF
usage: $0 SRC_POD DST_POD [namespace] [interface|all]

Examples:
  $0 test2-05-1 test1-05-1
  $0 test2-05-1 test1-05-1 default net2

Environment:
  K8CL             kubectl command to use. Default: kubectl
  PING_COUNT       ICMP packets per interface. Default: 2
  PING_TIMEOUT     Per-packet timeout seconds. Default: 1
  CAPTURE_SECONDS  tcpdump duration per interface. Default: 6
  SKIP_TCPDUMP     Set to 1 to skip tcpdump. Default: 0
  REPORT_DIR       Existing or new output directory. Default: /tmp/netop-cross-node-pods-<timestamp>
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
IFACE_FILTER=${1:-all}

REPORT_DIR=${REPORT_DIR:-/tmp/netop-cross-node-pods-$(date +%Y%m%d_%H%M%S)}
mkdir -p "${REPORT_DIR}"

SUMMARY="${REPORT_DIR}/summary.txt"
PAIRS_FILE="${REPORT_DIR}/interface-pairs.tsv"

function section()
{
  local name=${1}
  local file=${2}
  {
    echo
    echo "### ${name}"
    echo "# $(date -Is)"
  } >> "${file}"
}

function run_log()
{
  local name=${1}
  local file=${2}
  shift 2
  section "${name}" "${file}"
  {
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
  section "${pod}: ${name}" "${file}"
  {
    echo "$ ${K8CL} -n ${NS} exec ${pod} -- sh -c ${cmd}"
    ${K8CL} -n "${NS}" exec "${pod}" -- sh -c "${cmd}"
  } >> "${file}" 2>&1 || true
}

function get_network_status()
{
  local pod=${1}
  local file=${2}
  ${K8CL} -n "${NS}" get pod "${pod}" \
    -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' \
    > "${file}" 2>"${file}.err" || true
}

function start_capture()
{
  local pod=${1}
  local iface=${2}
  local file=${3}

  if [ "${SKIP_TCPDUMP}" = "1" ]; then
    echo "tcpdump skipped by SKIP_TCPDUMP=1" > "${file}"
    echo ""
    return
  fi

  (
    echo "# ${pod} ${iface} tcpdump started $(date -Is)"
    timeout "${CAPTURE_SECONDS}" "${K8CL}" -n "${NS}" exec "${pod}" -- \
      tcpdump -ni "${iface}" -e 'arp or icmp'
    echo "# ${pod} ${iface} tcpdump ended $(date -Is)"
  ) > "${file}" 2>&1 &
  echo $!
}

function collect_pod_basics()
{
  local pod=${1}
  local prefix=${2}

  run_log "${pod} get pod wide" "${REPORT_DIR}/${prefix}-pod.txt" \
    "${K8CL}" -n "${NS}" get pod "${pod}" -o wide
  run_log "${pod} describe" "${REPORT_DIR}/${prefix}-describe.txt" \
    "${K8CL}" -n "${NS}" describe pod "${pod}"
  run_log "${pod} yaml" "${REPORT_DIR}/${prefix}-pod.yaml" \
    "${K8CL}" -n "${NS}" get pod "${pod}" -o yaml
  pod_exec_log "${pod}" "ip -br addr" "${REPORT_DIR}/${prefix}-net.txt" \
    "ip -br addr"
  pod_exec_log "${pod}" "routes" "${REPORT_DIR}/${prefix}-net.txt" \
    "ip route show table all"
  pod_exec_log "${pod}" "links" "${REPORT_DIR}/${prefix}-links.txt" \
    "ip -d link show"
  pod_exec_log "${pod}" "neighbors" "${REPORT_DIR}/${prefix}-neigh.txt" \
    "ip neigh show"
}

function build_interface_pairs()
{
  local src_status=${1}
  local dst_status=${2}

  python3 - "${src_status}" "${dst_status}" "${IFACE_FILTER}" > "${PAIRS_FILE}" <<'PY'
import json
import sys

src_path, dst_path, iface_filter = sys.argv[1:4]

def load(path):
    raw = open(path, encoding="utf-8").read().strip()
    if not raw:
        return []
    return json.loads(raw)

def ip(entry):
    return (entry.get("ips") or [""])[0]

def pci(entry):
    return entry.get("device-info", {}).get("pci", {}).get("pci-address", "")

src = load(src_path)
dst = load(dst_path)
dst_by_iface = {e.get("interface", ""): e for e in dst}

for entry in src:
    iface = entry.get("interface", "")
    if not iface or iface == "eth0":
        continue
    if iface_filter != "all" and iface != iface_filter:
        continue
    peer = dst_by_iface.get(iface)
    if not peer:
        continue
    fields = [
        iface,
        entry.get("name", ""),
        ip(entry),
        ip(peer),
        entry.get("mac", ""),
        peer.get("mac", ""),
        pci(entry),
        pci(peer),
    ]
    print("\t".join(fields))
PY
}

function run_pair_test()
{
  local iface=${1}
  local network=${2}
  local src_ip=${3}
  local dst_ip=${4}
  local src_mac=${5}
  local dst_mac=${6}
  local src_pci=${7}
  local dst_pci=${8}

  local file="${REPORT_DIR}/${iface}-test.txt"
  local src_cap="${REPORT_DIR}/${iface}-src-tcpdump.txt"
  local dst_cap="${REPORT_DIR}/${iface}-dst-tcpdump.txt"

  {
    echo "interface: ${iface}"
    echo "network: ${network}"
    echo "source: ${SRC_POD} ${src_ip} ${src_mac} ${src_pci}"
    echo "dest: ${DST_POD} ${dst_ip} ${dst_mac} ${dst_pci}"
  } > "${file}"

  pod_exec_log "${SRC_POD}" "${iface} link before" "${file}" \
    "ip -d link show ${iface}; ip -s link show ${iface}; ip route get ${dst_ip}; ip neigh show dev ${iface}"

  pod_exec_log "${DST_POD}" "${iface} dest link before" "${file}" \
    "ip -d link show ${iface}; ip -s link show ${iface}; ip neigh show dev ${iface}"

  pod_exec_log "${SRC_POD}" "${iface} delete stale neighbor" "${file}" \
    "ip neigh del ${dst_ip} dev ${iface} 2>/dev/null || true; ip neigh show dev ${iface}"

  local src_pid=""
  local dst_pid=""
  src_pid=$(start_capture "${SRC_POD}" "${iface}" "${src_cap}")
  dst_pid=$(start_capture "${DST_POD}" "${iface}" "${dst_cap}")
  sleep 1

  pod_exec_log "${SRC_POD}" "${iface} ping" "${file}" \
    "ping -c ${PING_COUNT} -W ${PING_TIMEOUT} -I ${iface} ${dst_ip} || true"

  if [ -n "${src_pid}" ]; then wait "${src_pid}" 2>/dev/null || true; fi
  if [ -n "${dst_pid}" ]; then wait "${dst_pid}" 2>/dev/null || true; fi

  pod_exec_log "${SRC_POD}" "${iface} link after" "${file}" \
    "ip -s link show ${iface}; ip neigh show dev ${iface}; ip route get ${dst_ip}"
  pod_exec_log "${DST_POD}" "${iface} dest link after" "${file}" \
    "ip -s link show ${iface}; ip neigh show dev ${iface}"
}

{
  echo "Cross-node SR-IOV pod connectivity report"
  echo "time: $(date -Is)"
  echo "namespace: ${NS}"
  echo "source pod: ${SRC_POD}"
  echo "dest pod: ${DST_POD}"
  echo "interface filter: ${IFACE_FILTER}"
  echo "report dir: ${REPORT_DIR}"
  echo
} > "${SUMMARY}"

collect_pod_basics "${SRC_POD}" "src"
collect_pod_basics "${DST_POD}" "dst"

get_network_status "${SRC_POD}" "${REPORT_DIR}/src-network-status.json"
get_network_status "${DST_POD}" "${REPORT_DIR}/dst-network-status.json"

build_interface_pairs "${REPORT_DIR}/src-network-status.json" "${REPORT_DIR}/dst-network-status.json"

{
  echo "Interface pairs:"
  cat "${PAIRS_FILE}"
  echo
  echo "Interpretation hints:"
  echo "- TX packets increment plus INCOMPLETE/FAILED neighbor means ARP is transmitted but unanswered."
  echo "- No TX increment means pod kernel did not transmit on that interface."
  echo "- Source tcpdump may miss packets with SR-IOV/offloads; counters and neighbor state are more reliable."
  echo "- Destination tcpdump seeing no ARP while source TX increments points below CNI: VF/PF/switch L2."
} >> "${SUMMARY}"

if [ ! -s "${PAIRS_FILE}" ]; then
  echo "No matching secondary interfaces found. See network-status files in ${REPORT_DIR}." | tee -a "${SUMMARY}"
  exit 2
fi

while IFS=$'\t' read -r iface network src_ip dst_ip src_mac dst_mac src_pci dst_pci; do
  [ -n "${iface}" ] || continue
  run_pair_test "${iface}" "${network}" "${src_ip}" "${dst_ip}" "${src_mac}" "${dst_mac}" "${src_pci}" "${dst_pci}"
done < "${PAIRS_FILE}"

echo "Wrote report: ${REPORT_DIR}"
echo "Start with: ${SUMMARY}"
