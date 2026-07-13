#!/bin/bash
#
# Collect Calico/Tigera diagnostics used when Calico pods or APIService are failing.
#

set -uo pipefail

function usage()
{
  cat <<EOF
Usage: $0 [--report-dir DIR] [--node-cidrs CIDR[,CIDR...]] [--apply-fixes]

Collect a Calico diagnostic report and write an evidence-based fix plan.

Options:
  --report-dir DIR      Output directory. Default: /tmp/netop-calico-<timestamp>
  --node-cidrs CIDRS    Node InternalIP CIDR(s) for Calico autodetection.
                        Default: inferred /24 from the kubernetes service endpoint.
  --apply-fixes         Apply safe Kubernetes-side fixes after collection.
                        Currently patches Installation nodeAddressAutodetectionV4.
  -h, --help            Show this help.

Environment:
  CALICO_NODE_CIDRS     Same as --node-cidrs.
  REPORT_DIR            Same as --report-dir.
  K8CL                  kubectl command. Default: kubectl.
EOF
}

if [ -n "${NETOP_ROOT_DIR:-}" ] && [ -r "${NETOP_ROOT_DIR}/global_ops.cfg" ]; then
  user_cfg="${GLOBAL_OPS_USER:-${NETOP_ROOT_DIR}/global_ops_user.cfg}"
  if [ -r "${user_cfg}" ]; then
    # shellcheck source=/dev/null
    source "${NETOP_ROOT_DIR}/global_ops.cfg"
  fi
fi

K8CL=${K8CL:-kubectl}
REPORT_DIR=${REPORT_DIR:-}
APPLY_FIXES=${APPLY_FIXES:-0}
CALICO_NODE_CIDRS=${CALICO_NODE_CIDRS:-}
CALICO_NS=${CALICO_NS:-calico-system}
TIGERA_NS=${TIGERA_NS:-tigera-operator}
KUBE_NS=${KUBE_NS:-kube-system}

while [ $# -gt 0 ]; do
  case "${1}" in
  --report-dir)
    REPORT_DIR=${2:-}
    shift 2
    ;;
  --node-cidrs)
    CALICO_NODE_CIDRS=${2:-}
    shift 2
    ;;
  --apply-fixes|--fix)
    APPLY_FIXES=1
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
    REPORT_DIR=${1}
    shift
    ;;
  esac
done

REPORT_DIR=${REPORT_DIR:-/tmp/netop-calico-$(date +%Y%m%d_%H%M%S)}

mkdir -p "${REPORT_DIR}"
SUMMARY="${REPORT_DIR}/summary.txt"

read -r -a K8CL_CMD <<< "${K8CL}"

function kctl()
{
  "${K8CL_CMD[@]}" "$@"
}

function run_log()
{
  local label=${1}
  local file=${2}
  shift 2

  {
    echo "===== ${label} ====="
    echo "$ ${K8CL} $*"
    kctl "$@"
    echo
  } >> "${file}" 2>&1 || true
}

function run_shell()
{
  local label=${1}
  local file=${2}
  local cmd=${3}

  {
    echo "===== ${label} ====="
    echo "$ ${cmd}"
    bash -o pipefail -c "${cmd}"
    echo
  } >> "${file}" 2>&1 || true
}

function log_matching_pods()
{
  local ns=${1}
  local pattern=${2}
  local file=${3}
  local podref
  local pod

  while IFS= read -r podref; do
    [ -n "${podref}" ] || continue
    pod=${podref#pod/}
    run_log "${ns}/${pod} describe" "${file}" -n "${ns}" describe pod "${pod}"
    run_log "${ns}/${pod} logs" "${file}" -n "${ns}" logs "${pod}" --all-containers --tail=250
    run_log "${ns}/${pod} previous logs" "${file}" -n "${ns}" logs "${pod}" --all-containers --previous --tail=250
  done < <(kctl -n "${ns}" get pods -o name 2>/dev/null | grep -E "${pattern}" || true)
}

function cidr24_from_ip()
{
  local ip=${1}

  if [[ "${ip}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.0/24"
  fi
}

function cidrs_json_array()
{
  local input=${1// /}
  local out="["
  local cidr
  local -a cidrs

  IFS=',' read -r -a cidrs <<< "${input}"
  for cidr in "${cidrs[@]}"; do
    [ -n "${cidr}" ] || continue
    out="${out}\"${cidr}\","
  done
  out="${out%,}]"
  echo "${out}"
}

function infer_calico_node_cidrs()
{
  local endpoint_ip

  if [ -n "${CALICO_NODE_CIDRS}" ]; then
    echo "${CALICO_NODE_CIDRS}"
    return
  fi

  endpoint_ip=$(kctl get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | cut -d' ' -f1)
  cidr24_from_ip "${endpoint_ip}"
}

function apply_calico_autodetect_fix()
{
  local cidrs=${1}
  local cidrs_json
  local first_found

  if [ -z "${cidrs}" ]; then
    echo "ERROR: no Calico node CIDR available; pass --node-cidrs or CALICO_NODE_CIDRS" | tee -a "${REPORT_DIR}/fix-apply.txt"
    return 1
  fi

  cidrs_json=$(cidrs_json_array "${cidrs}")
  {
    echo "===== apply Calico nodeAddressAutodetectionV4 fix ====="
    echo "node CIDRs: ${cidrs}"
  } >> "${REPORT_DIR}/fix-apply.txt"

  first_found=$(kctl get installation.operator.tigera.io default -o jsonpath='{.spec.calicoNetwork.nodeAddressAutodetectionV4.firstFound}' 2>/dev/null || true)
  if [ -n "${first_found}" ]; then
    run_log "remove firstFound autodetection" "${REPORT_DIR}/fix-apply.txt" patch installation.operator.tigera.io default \
      --type=json -p='[{"op":"remove","path":"/spec/calicoNetwork/nodeAddressAutodetectionV4/firstFound"}]'
  fi

  run_log "set CIDR autodetection" "${REPORT_DIR}/fix-apply.txt" patch installation.operator.tigera.io default \
    --type=merge -p="{\"spec\":{\"calicoNetwork\":{\"nodeAddressAutodetectionV4\":{\"cidrs\":${cidrs_json}}}}}"

  run_log "restart calico-node" "${REPORT_DIR}/fix-apply.txt" -n "${CALICO_NS}" rollout restart daemonset/calico-node
  run_log "restart calico-kube-controllers" "${REPORT_DIR}/fix-apply.txt" -n "${CALICO_NS}" rollout restart deployment/calico-kube-controllers
  run_log "restart calico-apiserver" "${REPORT_DIR}/fix-apply.txt" -n "${CALICO_NS}" rollout restart deployment/calico-apiserver
}

function write_fix_plan()
{
  local file="${REPORT_DIR}/fix-plan.txt"
  local cidrs=${1}
  local installation="${REPORT_DIR}/installation.yaml"
  local logs="${REPORT_DIR}/logs.txt"
  local apiservices="${REPORT_DIR}/apiservices.txt"
  local needs_autodetect=0
  local has_timeout=0
  local missing_endpoints=0
  local expected_cidr
  local -a expected_cidrs

  grep -q 'firstFound:' "${installation}" 2>/dev/null && needs_autodetect=1
  grep -q 'nodeAddressAutodetectionV4:' "${installation}" 2>/dev/null && ! grep -q 'cidrs:' "${installation}" 2>/dev/null && needs_autodetect=1
  if [ -n "${cidrs}" ] && grep -q 'nodeAddressAutodetectionV4:' "${installation}" 2>/dev/null; then
    IFS=',' read -r -a expected_cidrs <<< "${cidrs// /}"
    for expected_cidr in "${expected_cidrs[@]}"; do
      [ -n "${expected_cidr}" ] || continue
      grep -q "${expected_cidr}" "${installation}" 2>/dev/null || needs_autodetect=1
    done
  fi
  grep -Eq '10\.96\.0\.1:443: i/o timeout|unable to load configmap based request-header-client-ca-file|Client.Timeout exceeded|context deadline exceeded' "${logs}" 2>/dev/null && has_timeout=1
  grep -Eq 'MissingEndpoints|False \(MissingEndpoints\)' "${apiservices}" 2>/dev/null && missing_endpoints=1

  {
    echo "Calico fix plan"
    echo "time: $(date -Is)"
    echo
    echo "Evidence flags:"
    echo "- firstFound/no-cidrs autodetection: ${needs_autodetect}"
    echo "- apiserver/kubernetes service timeout: ${has_timeout}"
    echo "- Calico APIService missing endpoints: ${missing_endpoints}"
    echo "- recommended node CIDRs: ${cidrs:-UNKNOWN}"
    echo
    if [ "${needs_autodetect}" = "1" ] || [ "${has_timeout}" = "1" ] || [ "${missing_endpoints}" = "1" ]; then
      echo "Recommended fix order:"
      echo "1. Ensure each Kubernetes node advertises the expected InternalIP."
      echo "   On each affected host, set kubelet --node-ip to the node's 10.185.x.x management/fabric IP, then restart kubelet."
      echo "   Existing helper:"
      echo "     sudo NETOP_ROOT_DIR=${NETOP_ROOT_DIR:-<repo>} ${NETOP_ROOT_DIR:-<repo>}/ops/kubelet-set.sh <node-ip>"
      echo
      echo "2. Patch Calico node autodetection away from firstFound and onto the node InternalIP CIDR."
      if [ -n "${cidrs}" ]; then
        echo "   Automatic Kubernetes-side apply:"
        echo "     ${0} --report-dir ${REPORT_DIR} --node-cidrs ${cidrs} --apply-fixes"
      else
        echo "   Automatic Kubernetes-side apply after choosing the node CIDR:"
        echo "     ${0} --report-dir ${REPORT_DIR} --node-cidrs 10.185.179.0/24 --apply-fixes"
      fi
      echo
      echo "3. Verify service routing from Calico pods:"
      echo "     ${K8CL} -n ${CALICO_NS} logs -l k8s-app=calico-apiserver --tail=100"
      echo "     ${K8CL} get apiservice v3.projectcalico.org"
      echo "     ${K8CL} get tigerastatuses.operator.tigera.io -A"
      echo
      echo "The --apply-fixes path only changes Kubernetes Calico resources and restarts Calico pods."
      echo "It does not edit host kubelet node-ip; that must be done on each node."
    else
      echo "No specific automated fix was inferred from the collected evidence."
      echo "Review logs.txt, apiservices.txt, rbac.txt, and kubernetes-service.txt."
    fi
  } > "${file}"
}

{
  echo "Calico debug report"
  echo "time: $(date -Is)"
  echo "report dir: ${REPORT_DIR}"
  echo
  echo "What this covers from the tmp Calico scripts:"
  echo "- Calico/Tigera pod status and Tigerastatus resources."
  echo "- Installation, IPPool, ClusterInformation, KubeControllersConfiguration, and FelixConfiguration state."
  echo "- RBAC checks for calico-kube-controllers, calico-node, and calico-apiserver."
  echo "- Current and previous logs for calico-kube-controllers, calico-node, calico-apiserver, and tigera-operator."
  echo "- APIService, Kubernetes service/endpoints, kube-proxy, and host CNI config checks."
  echo
  echo "Read these first:"
  echo "- pods.txt"
  echo "- tigera-status.txt"
  echo "- apiservices.txt"
  echo "- logs.txt"
  echo "- rbac.txt"
  echo "- kubernetes-service.txt"
  echo "- host-cni.txt"
  echo "- fix-plan.txt"
} > "${SUMMARY}"

run_shell "calico and tigera pods across namespaces" "${REPORT_DIR}/pods.txt" \
  "${K8CL} get pods -A -o wide | grep -E 'calico|tigera' || true"
run_log "calico-system pods" "${REPORT_DIR}/pods.txt" -n "${CALICO_NS}" get pods -o wide
run_log "tigera-operator pods" "${REPORT_DIR}/pods.txt" -n "${TIGERA_NS}" get pods -o wide

run_log "Tigerastatus resources" "${REPORT_DIR}/tigera-status.txt" get tigerastatuses.operator.tigera.io -A
run_log "Installation default describe" "${REPORT_DIR}/installation.txt" describe installation.operator.tigera.io default
run_log "Installation default yaml" "${REPORT_DIR}/installation.yaml" get installation.operator.tigera.io default -o yaml
run_log "IPPools" "${REPORT_DIR}/calico-crs.txt" get ippools.crd.projectcalico.org -o wide

run_log "Project Calico CRDs" "${REPORT_DIR}/crds.txt" get crd \
  clusterinformations.crd.projectcalico.org \
  kubecontrollersconfigurations.crd.projectcalico.org \
  felixconfigurations.crd.projectcalico.org \
  ippools.crd.projectcalico.org
run_log "ClusterInformation default" "${REPORT_DIR}/crds.txt" get clusterinformations.crd.projectcalico.org default -o yaml
run_log "KubeControllersConfiguration default" "${REPORT_DIR}/crds.txt" get kubecontrollersconfigurations.crd.projectcalico.org default -o yaml
run_log "FelixConfiguration default" "${REPORT_DIR}/crds.txt" get felixconfigurations.crd.projectcalico.org default -o yaml

run_log "calico-kube-controllers can get ClusterInformation" "${REPORT_DIR}/rbac.txt" auth can-i get clusterinformations.crd.projectcalico.org \
  --as system:serviceaccount:${CALICO_NS}:calico-kube-controllers
run_log "calico-kube-controllers can create ClusterInformation" "${REPORT_DIR}/rbac.txt" auth can-i create clusterinformations.crd.projectcalico.org \
  --as system:serviceaccount:${CALICO_NS}:calico-kube-controllers
run_log "calico-kube-controllers can update ClusterInformation" "${REPORT_DIR}/rbac.txt" auth can-i update clusterinformations.crd.projectcalico.org \
  --as system:serviceaccount:${CALICO_NS}:calico-kube-controllers
run_log "calico-node can get ClusterInformation" "${REPORT_DIR}/rbac.txt" auth can-i get clusterinformations.crd.projectcalico.org \
  --as system:serviceaccount:${CALICO_NS}:calico-node
run_log "calico-apiserver can get extension-apiserver-authentication" "${REPORT_DIR}/rbac.txt" auth can-i get configmaps/extension-apiserver-authentication \
  -n "${KUBE_NS}" --as system:serviceaccount:${CALICO_NS}:calico-apiserver

run_log "APIService v3.projectcalico.org" "${REPORT_DIR}/apiservices.txt" get apiservice v3.projectcalico.org -o yaml
run_log "APIService v1.crd.projectcalico.org" "${REPORT_DIR}/apiservices.txt" get apiservice v1.crd.projectcalico.org -o yaml
run_shell "all Calico APIService rows" "${REPORT_DIR}/apiservices.txt" \
  "${K8CL} get apiservice | grep -E 'projectcalico|calico' || true"

run_log "kubernetes service" "${REPORT_DIR}/kubernetes-service.txt" get svc kubernetes -o wide
run_log "kubernetes endpoints" "${REPORT_DIR}/kubernetes-service.txt" get endpoints kubernetes -o wide
run_log "kubernetes EndpointSlices" "${REPORT_DIR}/kubernetes-service.txt" -n default get endpointslice -l kubernetes.io/service-name=kubernetes -o wide
run_log "kube-system pods" "${REPORT_DIR}/kubernetes-service.txt" -n "${KUBE_NS}" get pods -o wide
run_log "kube-proxy logs" "${REPORT_DIR}/kube-proxy.txt" -n "${KUBE_NS}" logs -l k8s-app=kube-proxy --tail=250

log_matching_pods "${CALICO_NS}" 'calico-kube-controllers' "${REPORT_DIR}/logs.txt"
log_matching_pods "${CALICO_NS}" 'calico-node' "${REPORT_DIR}/logs.txt"
log_matching_pods "${CALICO_NS}" 'calico-apiserver' "${REPORT_DIR}/logs.txt"
log_matching_pods "${TIGERA_NS}" 'tigera-operator' "${REPORT_DIR}/logs.txt"

{
  echo "===== host CNI config ====="
  echo "$ ls -l /etc/cni/net.d"
  ls -l /etc/cni/net.d 2>&1 || true
  echo
  echo "$ ${K8CL} --kubeconfig=/etc/cni/net.d/calico-kubeconfig get clusterinformations.crd.projectcalico.org default"
  if [ -r /etc/cni/net.d/calico-kubeconfig ]; then
    kctl --kubeconfig=/etc/cni/net.d/calico-kubeconfig get clusterinformations.crd.projectcalico.org default 2>&1 || true
  else
    echo "WARN: /etc/cni/net.d/calico-kubeconfig is not readable on this host"
  fi
  echo
} > "${REPORT_DIR}/host-cni.txt"

CALICO_NODE_CIDRS=$(infer_calico_node_cidrs)
write_fix_plan "${CALICO_NODE_CIDRS}"

if [ "${APPLY_FIXES}" = "1" ]; then
  apply_calico_autodetect_fix "${CALICO_NODE_CIDRS}"
  {
    echo
    echo "Fix apply output:"
    echo "- fix-apply.txt"
  } >> "${SUMMARY}"
fi

echo "Wrote report: ${REPORT_DIR}"
echo "Start with: ${SUMMARY}"
