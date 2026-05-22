#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="20260522-operator-namespace-detect"
IMAGE="nvcr.io/nvstaging/mellanox/k8s-launch-kit:v26.4.0"
IMAGE_REPO="nvcr.io/nvstaging/mellanox/k8s-launch-kit"
IMAGE_TAG="v26.4.0"
NETWORK_OPERATOR_RELEASE="26.4"
L8K_TIMEOUT_SECONDS="${L8K_TIMEOUT_SECONDS:-1800}"
L8K_RUN_BACKEND="${L8K_RUN_BACKEND:-job}"
NCO_REPOSITORY="${NCO_REPOSITORY:-nvcr.io/nvstaging/mellanox}"
NCO_VERSION="${NCO_VERSION:-network-operator-v26.4.0-beta.7}"
NCO_IMAGE_PULL_SECRET="${NCO_IMAGE_PULL_SECRET:-ngc-image-secret}"
NCO_PATCH_GUARD_STOP_FILE="/tmp/l8k-nco-patch-guard.stop"
NCO_PATCH_GUARD_PID_FILE="/tmp/l8k-nco-patch-guard.pid"

WORKDIR="/cm/shared/netop-tools"
KUBEDIR="/root/.kube"
KEY_FILE="./thuff_ngc_staging_personal_key"
CONTAINER_WORKING_DIR="/work"
L8K_ASSET_ARCHIVE_URL="${L8K_ASSET_ARCHIVE_URL:-https://github.com/NVIDIA/k8s-launch-kit/archive/refs/heads/main.tar.gz}"

HOST_KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
WORK_KUBECONFIG="${WORKDIR}/kubeconfig"
CONTAINER_KUBECONFIG="/work/kubeconfig"
L8K_BASE_CONFIG="${WORKDIR}/l8k-config.yaml"
CONTAINER_L8K_BASE_CONFIG="/work/l8k-config.yaml"

DEFAULT_NODE_SELECTOR="feature.node.kubernetes.io/pci-15b3.present=true"
DISCOVERY_LABEL_KEY="network.nvidia.com/l8k-discover"
DISCOVERY_LABEL="${DISCOVERY_LABEL_KEY}=true"

POD_JSON="l8k-pod.json"
CONTAINER_JSON="l8k-container.json"
LAST_LOG="${WORKDIR}/l8k-last.log"
LAST_INSPECT="${WORKDIR}/l8k-last-container-inspect.json"
CRI_LOG_DIR="${WORKDIR}/cri-logs"
CRI_POD_NAMESPACE="netop-tools"
CRI_POD_NAME="l8k-crictl"
CRI_CONTAINER_NAME="l8k"
CRI_POD_UID_FILE="${WORKDIR}/.l8k-cri-pod-uid"
CRI_LOG_PATH="${CRI_CONTAINER_NAME}/0.log"
NCP_BACKUP_DIR="${WORKDIR}/backups"
NCP_BACKUP_FILE="${NCP_BACKUP_DIR}/nicclusterpolicy-before-active-discovery.json"
NCP_RESTORE_FILE="${NCP_BACKUP_DIR}/nicclusterpolicy-restore.json"
DEBUG_DIR="${WORKDIR}/debug"
NETWORK_OPERATOR_NAMESPACE="${NETWORK_OPERATOR_NAMESPACE:-}"
DISCOVERY_NAMESPACE="${DISCOVERY_NAMESPACE:-}"

K8S_JOB_NAMESPACE="${K8S_JOB_NAMESPACE:-}"
K8S_JOB_NAME="${K8S_JOB_NAME:-l8k-run}"
K8S_JOB_CONTAINER_NAME="${K8S_JOB_CONTAINER_NAME:-l8k}"
K8S_JOB_MANIFEST="${WORKDIR}/l8k-job.yaml"
K8S_JOB_IMAGE_PULL_SECRET="${K8S_JOB_IMAGE_PULL_SECRET:-${NCO_IMAGE_PULL_SECRET}}"
K8S_JOB_NODE_NAME="${K8S_JOB_NODE_NAME:-}"
K8S_JOB_BACKOFF_LIMIT="${K8S_JOB_BACKOFF_LIMIT:-0}"
K8S_JOB_ACTIVE_DEADLINE_SECONDS="${K8S_JOB_ACTIVE_DEADLINE_SECONDS:-${L8K_TIMEOUT_SECONDS}}"

function endpoints() {
  cat >/etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 30
debug: false
pull-image-on-create: false
EOF
}

function kctl() {
  kubectl --kubeconfig "${HOST_KUBECONFIG}" "$@"
}

function detect_network_operator_namespace() {
  local ns
  local candidates=()

  [ -n "${NETWORK_OPERATOR_NAMESPACE}" ] && candidates+=("${NETWORK_OPERATOR_NAMESPACE}")
  [ -n "${DISCOVERY_NAMESPACE}" ] && candidates+=("${DISCOVERY_NAMESPACE}")
  [ -n "${K8S_JOB_NAMESPACE}" ] && candidates+=("${K8S_JOB_NAMESPACE}")
  candidates+=("network-operator" "nvidia-network-operator")

  for ns in "${candidates[@]}"; do
    [ -n "${ns}" ] || continue
    if kctl get namespace "${ns}" >/dev/null 2>&1; then
      if kctl -n "${ns}" get daemonset nic-configuration-daemon >/dev/null 2>&1 \
        || kctl -n "${ns}" get secret "${K8S_JOB_IMAGE_PULL_SECRET}" >/dev/null 2>&1 \
        || kctl -n "${ns}" get pods >/dev/null 2>&1; then
        echo "${ns}"
        return 0
      fi
    fi
  done

  ns="$(kctl get daemonset -A -o jsonpath='{range .items[?(@.metadata.name=="nic-configuration-daemon")]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | head -n 1 || true)"
  if [ -n "${ns}" ]; then
    echo "${ns}"
    return 0
  fi

  ns="$(kctl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | awk '$2 ~ /^(network-operator|nic-configuration|nic-feature|mofed|sriov|rdma)/ {print $1; exit}' || true)"
  if [ -n "${ns}" ]; then
    echo "${ns}"
    return 0
  fi

  echo "network-operator"
}

function configure_cluster_namespaces() {
  local ns
  ns="$(detect_network_operator_namespace)"

  if [ -z "${NETWORK_OPERATOR_NAMESPACE}" ]; then
    NETWORK_OPERATOR_NAMESPACE="${ns}"
  fi
  if [ -z "${DISCOVERY_NAMESPACE}" ]; then
    DISCOVERY_NAMESPACE="${NETWORK_OPERATOR_NAMESPACE}"
  fi
  if [ -z "${K8S_JOB_NAMESPACE}" ]; then
    K8S_JOB_NAMESPACE="${NETWORK_OPERATOR_NAMESPACE}"
  fi
}

function pull_image() {
  if [ ! -f "${KEY_FILE}" ]; then
    echo "Missing NGC API key file: ${KEY_FILE}"
    exit 1
  fi

  local ngc_api_key
  ngc_api_key="$(tr -d '\r\n' < "${KEY_FILE}")"
  crictl pull --creds '$oauthtoken':"${ngc_api_key}" "${IMAGE}"
}

function prepare_kubeconfig() {
  if [ ! -f "${HOST_KUBECONFIG}" ]; then
    echo "Missing host kubeconfig: ${HOST_KUBECONFIG}"
    exit 1
  fi

  cp "${HOST_KUBECONFIG}" "${WORK_KUBECONFIG}"
  chmod 0644 "${WORK_KUBECONFIG}"
}

function sync_l8k_config_namespace() {
  local current_namespace
  local tmp_file
  local backup_file

  [ -s "${L8K_BASE_CONFIG}" ] || return 0
  configure_cluster_namespaces

  current_namespace="$(awk '
    /^networkOperator:[[:space:]]*$/ {in_netop=1; next}
    in_netop && /^[^[:space:]]/ {in_netop=0}
    in_netop && /^[[:space:]]+namespace:[[:space:]]*/ {
      sub(/^[[:space:]]+namespace:[[:space:]]*/, "")
      print
      exit
    }
  ' "${L8K_BASE_CONFIG}" 2>/dev/null || true)"

  if [ "${current_namespace}" = "${NETWORK_OPERATOR_NAMESPACE}" ]; then
    return 0
  fi

  backup_file="${L8K_BASE_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
  tmp_file="${L8K_BASE_CONFIG}.tmp.$$"
  cp "${L8K_BASE_CONFIG}" "${backup_file}"

  awk -v ns="${NETWORK_OPERATOR_NAMESPACE}" '
    BEGIN { in_netop=0; wrote=0 }
    /^networkOperator:[[:space:]]*$/ {
      in_netop=1
      print
      next
    }
    in_netop && /^[^[:space:]]/ {
      if (!wrote) {
        print "  namespace: " ns
        wrote=1
      }
      in_netop=0
    }
    in_netop && /^[[:space:]]+namespace:[[:space:]]*/ {
      if (!wrote) {
        print "  namespace: " ns
        wrote=1
      }
      next
    }
    { print }
    END {
      if (in_netop && !wrote) {
        print "  namespace: " ns
      }
    }
  ' "${L8K_BASE_CONFIG}" >"${tmp_file}"

  mv "${tmp_file}" "${L8K_BASE_CONFIG}"
  echo "Updated ${L8K_BASE_CONFIG} networkOperator.namespace: ${current_namespace:-<missing>} -> ${NETWORK_OPERATOR_NAMESPACE}"
  echo "Saved previous config: ${backup_file}"
}

function ensure_l8k_config() {
  configure_cluster_namespaces

  if [ -s "${L8K_BASE_CONFIG}" ]; then
    sync_l8k_config_namespace
    return
  fi

  cat >"${L8K_BASE_CONFIG}" <<EOF
networkOperator:
  namespace: ${NETWORK_OPERATOR_NAMESPACE}
  repository: nvcr.io/nvidia/cloud-native
  docsBaseURL: https://docs.nvidia.com/networking/display/kubernetes2610

docaDriver:
  unloadStorageModules: false
  enableNFSRDMA: false

nvIpam:
  poolName: nv-ipam-pool
  subnets:
  - subnet: 192.168.100.0/24
    gateway: 192.168.100.1
  - subnet: 192.168.101.0/24
    gateway: 192.168.101.1
  - subnet: 192.168.102.0/24
    gateway: 192.168.102.1
  - subnet: 192.168.103.0/24
    gateway: 192.168.103.1

sriov:
  ethernetMtu: 9000
  infinibandMtu: 4000
  numVfs: 8
  priority: 90
  resourceName: sriov_resource
  networkName: sriov-network

hostdev:
  resourceName: hostdev-resource
  networkName: hostdev-network

rdmaShared:
  resourceName: rdma_shared_resource
  hcaMax: 63

ipoib:
  networkName: ipoib-network

macvlan:
  networkName: macvlan-network

spectrumX:
  nicType: "1023"
  overlay: "none"
  rdmaPrefix: "roce_p%plane%_r%rail%"
  netdevPrefix: "eth_p%plane%_r%rail%"

profile:
  fabric: ethernet
  deployment: sriov
  multirail: true
  ai: false
EOF

  chmod 0644 "${L8K_BASE_CONFIG}"
}

function copy_asset_dir() {
  local src_root="$1"
  local dir_name="$2"
  local dst="${WORKDIR}/${dir_name}"

  if [ "${dir_name}" = "profiles" ] && profile_assets_valid "${dst}"; then
    return
  fi

  if [ "${dir_name}" != "profiles" ] && [ -d "${dst}" ] && find "${dst}" -type f | grep -q .; then
    return
  fi

  local found
  if [ -d "${src_root}/${dir_name}" ]; then
    found="${src_root}/${dir_name}"
  else
    found="$(find "${src_root}" -type d -name "${dir_name}" | while read -r candidate; do
      if [ "${dir_name}" != "profiles" ] || profile_assets_valid "${candidate}"; then
        echo "${candidate}"
        break
      fi
    done)"
  fi

  if [ -z "${found}" ]; then
    return
  fi

  rm -rf "${dst}"
  cp -a "${found}" "${dst}"
}

function profile_assets_valid() {
  local dir="${1:-}"
  [ -d "${dir}" ] || return 1
  find "${dir}" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.tmpl' -o -name '*.tpl' \) | grep -q .
}

function verify_profile_assets() {
  local dir="${WORKDIR}/profiles"

  if ! profile_assets_valid "${dir}"; then
    echo "Invalid Launch Kit profile assets under ${dir}"
    if [ -d "${dir}" ]; then
      echo "Current profile directory contents:"
      find "${dir}" -maxdepth 5 -type f | sort
    else
      echo "Profile directory does not exist."
    fi
    exit 1
  fi

  echo
  echo "Verified Launch Kit profile assets under ${dir}:"
  find "${dir}" -maxdepth 5 -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '*.tmpl' -o -name '*.tpl' \) | sort | head -n 40
}

function ensure_l8k_assets() {
  if profile_assets_valid "${WORKDIR}/profiles"; then
    return
  fi

  if [ -d "${WORKDIR}/profiles" ]; then
    echo "Removing invalid Launch Kit profiles directory: ${WORKDIR}/profiles"
    rm -rf "${WORKDIR}/profiles"
  fi

  echo "Launch Kit profile assets not found under ${WORKDIR}/profiles"
  echo "Fetching Launch Kit assets from ${L8K_ASSET_ARCHIVE_URL}"

  local asset_tmp="${WORKDIR}/.l8k-assets-tmp"
  local archive="${asset_tmp}/k8s-launch-kit.tar.gz"
  local src_root

  rm -rf "${asset_tmp}"
  mkdir -p "${asset_tmp}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${L8K_ASSET_ARCHIVE_URL}" -o "${archive}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${archive}" "${L8K_ASSET_ARCHIVE_URL}"
  else
    echo "Neither curl nor wget is available; cannot fetch Launch Kit profile assets."
    exit 1
  fi

  mkdir -p "${asset_tmp}/src"
  tar -xzf "${archive}" -C "${asset_tmp}/src"
  src_root="$(find "${asset_tmp}/src" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"

  if [ -z "${src_root}" ]; then
    echo "Unable to locate extracted Launch Kit source root."
    exit 1
  fi

  copy_asset_dir "${src_root}" profiles
  copy_asset_dir "${src_root}" templates

  if ! profile_assets_valid "${WORKDIR}/profiles"; then
    echo "Launch Kit profiles were not found in downloaded archive."
    echo "Archive source: ${L8K_ASSET_ARCHIVE_URL}"
    exit 1
  fi

  rm -rf "${asset_tmp}"
  echo "Launch Kit profiles staged at ${WORKDIR}/profiles"
  verify_profile_assets
}

function image_ref() {
  crictl images | awk -v repo="${IMAGE_REPO}" -v tag="${IMAGE_TAG}" \
    '$1 == repo && $2 == tag {print $3; exit}'
}

function json_escape() {
  local value="${1}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/}"
  printf '%s' "${value}"
}

function write_json_array() {
  local first=1
  printf '['
  for arg in "$@"; do
    if [ "${first}" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "${arg}")"
  done
  printf ']'
}

function new_cri_pod_uid() {
  local uid
  uid="l8k-$(date +%s%N)"
  echo "${uid}" >"${CRI_POD_UID_FILE}"
  echo "${uid}"
}

function current_cri_pod_uid() {
  if [ -s "${CRI_POD_UID_FILE}" ]; then
    cat "${CRI_POD_UID_FILE}"
  else
    new_cri_pod_uid
  fi
}

function current_cri_pod_log_dir() {
  local uid
  uid="$(current_cri_pod_uid)"
  echo "/var/log/pods/${CRI_POD_NAMESPACE}_${CRI_POD_NAME}_${uid}"
}

function copy_cri_log_to() {
  local dest="$1"
  local pod_log_dir
  pod_log_dir="$(current_cri_pod_log_dir)"

  if [ -s "${pod_log_dir}/${CRI_LOG_PATH}" ]; then
    cp "${pod_log_dir}/${CRI_LOG_PATH}" "${dest}" 2>/dev/null || true
  elif [ -s "${CRI_LOG_DIR}/${CRI_LOG_PATH}" ]; then
    cp "${CRI_LOG_DIR}/${CRI_LOG_PATH}" "${dest}" 2>/dev/null || true
  fi
}

function append_cri_log_to() {
  local dest="$1"
  local pod_log_dir
  pod_log_dir="$(current_cri_pod_log_dir)"

  if [ -s "${pod_log_dir}/${CRI_LOG_PATH}" ]; then
    cat "${pod_log_dir}/${CRI_LOG_PATH}" >>"${dest}" 2>/dev/null || true
  elif [ -s "${CRI_LOG_DIR}/${CRI_LOG_PATH}" ]; then
    cat "${CRI_LOG_DIR}/${CRI_LOG_PATH}" >>"${dest}" 2>/dev/null || true
  fi
}

function write_pod_json() {
  local pod_uid
  local pod_log_dir
  pod_uid="$(current_cri_pod_uid)"
  pod_log_dir="$(current_cri_pod_log_dir)"

  mkdir -p "${CRI_LOG_DIR}/${CRI_CONTAINER_NAME}" "${pod_log_dir}/${CRI_CONTAINER_NAME}"
  touch "${CRI_LOG_DIR}/${CRI_LOG_PATH}" "${pod_log_dir}/${CRI_LOG_PATH}"
  chmod 0666 "${CRI_LOG_DIR}/${CRI_LOG_PATH}" "${pod_log_dir}/${CRI_LOG_PATH}" || true

  cat >"${POD_JSON}" <<EOF
{
  "metadata": {
    "name": "$(json_escape "${CRI_POD_NAME}")",
    "namespace": "$(json_escape "${CRI_POD_NAMESPACE}")",
    "uid": "$(json_escape "${pod_uid}")",
    "attempt": 1
  },
  "log_directory": "$(json_escape "${pod_log_dir}")",
  "linux": {
    "cgroup_parent": "/system.slice",
    "security_context": {
      "namespace_options": {
        "network": 2
      }
    }
  }
}
EOF
}

function write_container_json() {
  if [ -z "$(image_ref)" ]; then
    pull_image
  fi

  if [ -z "$(image_ref)" ]; then
    echo "Unable to find local image ref for ${IMAGE}"
    exit 1
  fi

  local args_json
  args_json="$(write_json_array "$@")"

  cat >"${CONTAINER_JSON}" <<EOF
{
  "metadata": {
    "name": "$(json_escape "${CRI_CONTAINER_NAME}")"
  },
  "image": {
    "image": "$(json_escape "${IMAGE}")"
  },
  "args": ${args_json},
  "working_dir": "$(json_escape "${CONTAINER_WORKING_DIR}")",
  "mounts": [
    {
      "host_path": "$(json_escape "${KUBEDIR}")",
      "container_path": "/root/.kube"
    },
    {
      "host_path": "$(json_escape "${WORKDIR}")",
      "container_path": "/work"
    }
  ],
  "log_path": "$(json_escape "${CRI_LOG_PATH}")",
  "stdin": false,
  "tty": false,
  "linux": {}
}
EOF
}

function get_pod() {
  crictl pods --name "${CRI_POD_NAME}" --quiet 2>/dev/null | head -n1 || true
}

function start_pod() {
  write_pod_json

  local pod_id
  pod_id="$(get_pod)"

  if [ -n "${pod_id}" ]; then
    echo "Launch Kit pod sandbox already exists: ${pod_id}"
    crictl pods --name "${CRI_POD_NAME}"
    return
  fi

  pod_id="$(crictl runp "${POD_JSON}")"
  echo "Launch Kit pod sandbox: ${pod_id}"
  crictl pods --name "${CRI_POD_NAME}"
}

function run_l8k_cri() {
  endpoints
  prepare_kubeconfig
  ensure_l8k_config
  ensure_l8k_assets
  : >"${LAST_LOG}"
  mkdir -p "${CRI_LOG_DIR}/${CRI_CONTAINER_NAME}"
  : >"${CRI_LOG_DIR}/${CRI_LOG_PATH}"
  echo "launchkit.sh version: ${SCRIPT_VERSION}"

  # Each l8k CLI execution is a short-lived CRI container. Reusing a stale
  # sandbox can create containers under a pod sandbox container that already
  # exited, so start each invocation from a clean l8k sandbox.
  stop_all
  start_pod >/dev/null

  local pod_id
  pod_id="$(get_pod)"

  if [ -z "${pod_id}" ]; then
    echo "No l8k pod sandbox found"
    exit 1
  fi

  write_container_json "$@"

  local cid
  echo
  echo "Running l8k args: $*"
  cid="$(crictl create --no-pull "${pod_id}" "${CONTAINER_JSON}" "${POD_JSON}")"
  echo "CRI container: ${cid}"

  local start_output
  local start_status
  set +e
  start_output="$(crictl start "${cid}" 2>&1)"
  start_status=$?
  set -e

  if [ "${start_status}" -ne 0 ]; then
    printf '%s\n' "${start_output}" | tee -a "${LAST_LOG}"
    crictl inspect "${cid}" >"${LAST_INSPECT}" 2>/dev/null || true
    if ! crictl logs "${cid}" >>"${LAST_LOG}" 2>&1; then
      append_cri_log_to "${LAST_LOG}"
    fi
    echo
    echo "l8k container failed to start"
    crictl inspect "${cid}" | jq -r '
      "state: \(.status.state)",
      "exitCode: \(.status.exitCode)",
      "reason: \(.status.reason // "")",
      "message: \(.status.message // "")"
    ' 2>/dev/null || true
    echo
    echo "Container config kept for debugging: ${CONTAINER_JSON}"
    echo "Saved last log: ${LAST_LOG}"
    echo "Saved last inspect: ${LAST_INSPECT}"
    if [ "${L8K_COLLECT_CLUSTER_DIAGNOSTICS:-false}" = "true" ]; then
      collect_cluster_diagnostics
    fi
    echo
    echo "Leaving failed container for inspection: ${cid}"
    echo "Run '$0 stop' to clean up l8k CRI containers and pod sandboxes."
    collect_runtime_failure_debug "${cid}" "${start_status}"
    return "${start_status}"
  fi

  local state
  local timed_out=1
  for _ in $(seq 1 "${L8K_TIMEOUT_SECONDS}"); do
    state="$(crictl inspect "${cid}" | jq -r '.status.state')"
    if [ "${state}" = "CONTAINER_EXITED" ]; then
      timed_out=0
      break
    fi
    sleep 1
  done

  if [ "${timed_out}" -eq 1 ]; then
    echo
    echo "l8k timed out after ${L8K_TIMEOUT_SECONDS}s; leaving container for inspection: ${cid}"
    crictl inspect "${cid}" >"${LAST_INSPECT}" 2>/dev/null || true
    if ! crictl logs "${cid}" >"${LAST_LOG}" 2>&1; then
      copy_cri_log_to "${LAST_LOG}"
    fi
    cat "${LAST_LOG}" || true
    if [ "${L8K_COLLECT_CLUSTER_DIAGNOSTICS:-false}" = "true" ]; then
      collect_cluster_diagnostics
    fi
    echo
    echo "Saved last log: ${LAST_LOG}"
    echo "Saved last inspect: ${LAST_INSPECT}"
    collect_runtime_failure_debug "${cid}" 124
    return 124
  fi

  if ! crictl logs "${cid}" >"${LAST_LOG}" 2>&1; then
    copy_cri_log_to "${LAST_LOG}"
  fi
  cat "${LAST_LOG}" || true
  crictl inspect "${cid}" >"${LAST_INSPECT}" 2>/dev/null || true

  local exit_code
  exit_code="$(crictl inspect "${cid}" | jq -r '.status.exitCode // 0')"

  if [ "${exit_code}" != "0" ]; then
    echo
    echo "l8k container failed"
    crictl inspect "${cid}" | jq -r '
      "state: \(.status.state)",
      "exitCode: \(.status.exitCode)",
      "reason: \(.status.reason // "")",
      "message: \(.status.message // "")"
    '
    echo
    echo "Container config kept for debugging: ${CONTAINER_JSON}"
    echo "Saved last log: ${LAST_LOG}"
    echo "Saved last inspect: ${LAST_INSPECT}"
    if [ "${L8K_COLLECT_CLUSTER_DIAGNOSTICS:-false}" = "true" ]; then
      collect_cluster_diagnostics
    fi
    echo
    echo "Leaving failed container for inspection: ${cid}"
    echo "Run '$0 stop' to clean up l8k CRI containers and pod sandboxes."
    collect_runtime_failure_debug "${cid}" "${exit_code}"
    return "${exit_code}"
  fi

  crictl rm "${cid}" >/dev/null 2>&1 || true
  stop_all

  return "${exit_code}"
}

function yaml_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

function write_yaml_args() {
  for arg in "$@"; do
    printf '            - '
    yaml_quote "${arg}"
    printf '\n'
  done
}

function resolve_k8s_job_node_name() {
  if [ -n "${K8S_JOB_NODE_NAME}" ]; then
    echo "${K8S_JOB_NODE_NAME}"
  else
    hostname -s
  fi
}

function ensure_k8s_job_namespace() {
  configure_cluster_namespaces

  if ! kctl get namespace "${K8S_JOB_NAMESPACE}" >/dev/null 2>&1; then
    kctl create namespace "${K8S_JOB_NAMESPACE}"
  fi

  if ! kctl -n "${K8S_JOB_NAMESPACE}" get secret "${K8S_JOB_IMAGE_PULL_SECRET}" >/dev/null 2>&1; then
    echo "WARNING: imagePullSecret ${K8S_JOB_IMAGE_PULL_SECRET} was not found in namespace ${K8S_JOB_NAMESPACE}."
    echo "         Set NETWORK_OPERATOR_NAMESPACE/K8S_JOB_NAMESPACE to the namespace that has it, or create/copy the secret there."
  fi
}

function write_l8k_job_manifest() {
  local node_name
  node_name="$(resolve_k8s_job_node_name)"

  cat >"${K8S_JOB_MANIFEST}" <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${K8S_JOB_NAME}
  namespace: ${K8S_JOB_NAMESPACE}
  labels:
    app.kubernetes.io/name: k8s-launch-kit
    app.kubernetes.io/managed-by: launchkit-sh
spec:
  backoffLimit: ${K8S_JOB_BACKOFF_LIMIT}
  activeDeadlineSeconds: ${K8S_JOB_ACTIVE_DEADLINE_SECONDS}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: k8s-launch-kit
        app.kubernetes.io/managed-by: launchkit-sh
    spec:
      restartPolicy: Never
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      nodeName: ${node_name}
      tolerations:
        - operator: Exists
      imagePullSecrets:
        - name: ${K8S_JOB_IMAGE_PULL_SECRET}
      containers:
        - name: ${K8S_JOB_CONTAINER_NAME}
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          workingDir: /work
          args:
$(write_yaml_args "$@")
          volumeMounts:
            - name: netop-tools
              mountPath: /work
      volumes:
        - name: netop-tools
          hostPath:
            path: ${WORKDIR}
            type: Directory
EOF
}

function collect_k8s_job_failure_debug() {
  local debug_path
  local archive_path
  local pod_name

  configure_cluster_namespaces

  mkdir -p "${DEBUG_DIR}"
  debug_path="${DEBUG_DIR}/l8k-job-failure-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${debug_path}"

  pod_name="$(kctl -n "${K8S_JOB_NAMESPACE}" get pods -l job-name="${K8S_JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

  cp "${K8S_JOB_MANIFEST}" "${debug_path}/l8k-job.yaml" 2>/dev/null || true
  cp "${LAST_LOG}" "${debug_path}/l8k-last.log" 2>/dev/null || true
  kctl -n "${K8S_JOB_NAMESPACE}" get job "${K8S_JOB_NAME}" -o yaml >"${debug_path}/job.yaml" 2>&1 || true
  kctl -n "${K8S_JOB_NAMESPACE}" describe job "${K8S_JOB_NAME}" >"${debug_path}/job-describe.txt" 2>&1 || true
  if [ -n "${pod_name}" ]; then
    kctl -n "${K8S_JOB_NAMESPACE}" get pod "${pod_name}" -o yaml >"${debug_path}/pod.yaml" 2>&1 || true
    kctl -n "${K8S_JOB_NAMESPACE}" describe pod "${pod_name}" >"${debug_path}/pod-describe.txt" 2>&1 || true
    kctl -n "${K8S_JOB_NAMESPACE}" logs "${pod_name}" --all-containers=true >"${debug_path}/pod.log" 2>&1 || true
  fi
  kctl -n "${K8S_JOB_NAMESPACE}" get events --sort-by=.lastTimestamp >"${debug_path}/events.txt" 2>&1 || true
  collect_cluster_diagnostics >"${debug_path}/network-operator-diagnostics.txt" 2>&1 || true

  archive_path="${debug_path}.tar.gz"
  tar -C "${DEBUG_DIR}" -czf "${archive_path}" "$(basename "${debug_path}")" 2>/dev/null || true

  echo
  echo "Kubernetes Job failure debug bundle directory: ${debug_path}"
  echo "Kubernetes Job failure debug bundle archive: ${archive_path}"
}

function run_l8k_job() {
  prepare_kubeconfig
  ensure_l8k_config
  ensure_l8k_assets
  ensure_k8s_job_namespace
  : >"${LAST_LOG}"

  echo "launchkit.sh version: ${SCRIPT_VERSION}"
  echo "Launch Kit backend: kubernetes Job"
  echo "Job namespace/name: ${K8S_JOB_NAMESPACE}/${K8S_JOB_NAME}"
  echo "Job node: $(resolve_k8s_job_node_name)"

  write_l8k_job_manifest "$@"

  echo
  echo "Running l8k args: $*"
  echo "Job manifest: ${K8S_JOB_MANIFEST}"

  kctl -n "${K8S_JOB_NAMESPACE}" delete job "${K8S_JOB_NAME}" --ignore-not-found=true >/dev/null 2>&1 || true
  kctl apply -f "${K8S_JOB_MANIFEST}"

  local pod_name=""
  local status=""
  local exit_code="1"
  local timed_out=1

  for _ in $(seq 1 60); do
    pod_name="$(kctl -n "${K8S_JOB_NAMESPACE}" get pods -l job-name="${K8S_JOB_NAME}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    [ -n "${pod_name}" ] && break
    sleep 1
  done

  if [ -n "${pod_name}" ]; then
    echo "Job pod: ${pod_name}"
  else
    echo "No pod created for job ${K8S_JOB_NAMESPACE}/${K8S_JOB_NAME}"
  fi

  for _ in $(seq 1 "${L8K_TIMEOUT_SECONDS}"); do
    status="$(kctl -n "${K8S_JOB_NAMESPACE}" get job "${K8S_JOB_NAME}" -o jsonpath='{.status.succeeded}:{.status.failed}' 2>/dev/null || true)"
    case "${status}" in
      1:*)
        timed_out=0
        exit_code=0
        break
        ;;
      *:1|*:2|*:3|*:4|*:5)
        timed_out=0
        exit_code=1
        break
        ;;
    esac

    if [ -n "${pod_name}" ]; then
      local phase
      phase="$(kctl -n "${K8S_JOB_NAMESPACE}" get pod "${pod_name}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [ "${phase}" = "Failed" ] || [ "${phase}" = "Succeeded" ]; then
        timed_out=0
        break
      fi
    fi
    sleep 1
  done

  if [ -n "${pod_name}" ]; then
    kctl -n "${K8S_JOB_NAMESPACE}" logs "${pod_name}" --all-containers=true >"${LAST_LOG}" 2>&1 || true
    cat "${LAST_LOG}" || true
    exit_code="$(kctl -n "${K8S_JOB_NAMESPACE}" get pod "${pod_name}" -o json | jq -r '
      [.status.containerStatuses[]? | select(.name == "'"${K8S_JOB_CONTAINER_NAME}"'") | .state.terminated.exitCode][0] // empty
    ' 2>/dev/null || true)"
    [ -n "${exit_code}" ] || exit_code="1"
  fi

  if [ "${timed_out}" -eq 1 ]; then
    echo
    echo "l8k Kubernetes Job timed out after ${L8K_TIMEOUT_SECONDS}s."
    if [ "${L8K_COLLECT_CLUSTER_DIAGNOSTICS:-false}" = "true" ]; then
      collect_cluster_diagnostics
    fi
    collect_k8s_job_failure_debug
    return 124
  fi

  if [ "${exit_code}" != "0" ]; then
    echo
    echo "l8k Kubernetes Job failed"
    echo "namespace: ${K8S_JOB_NAMESPACE}"
    echo "job: ${K8S_JOB_NAME}"
    echo "pod: ${pod_name}"
    echo "exitCode: ${exit_code}"
    echo
    echo "Saved last log: ${LAST_LOG}"
    if [ "${L8K_COLLECT_CLUSTER_DIAGNOSTICS:-false}" = "true" ]; then
      collect_cluster_diagnostics
    fi
    collect_k8s_job_failure_debug
    return "${exit_code}"
  fi

  kctl -n "${K8S_JOB_NAMESPACE}" delete job "${K8S_JOB_NAME}" --ignore-not-found=true >/dev/null 2>&1 || true
  return 0
}

function run_l8k() {
  case "${L8K_RUN_BACKEND}" in
    job|k8s|kubernetes)
      run_l8k_job "$@"
      ;;
    cri|crictl)
      run_l8k_cri "$@"
      ;;
    *)
      echo "Unknown L8K_RUN_BACKEND=${L8K_RUN_BACKEND}; expected job or cri"
      return 1
      ;;
  esac
}

function stop_all() {
  configure_cluster_namespaces

  kctl -n "${K8S_JOB_NAMESPACE}" delete job "${K8S_JOB_NAME}" --ignore-not-found=true >/dev/null 2>&1 || true

  for cid in $(crictl ps -a --name "${CRI_CONTAINER_NAME}" --quiet 2>/dev/null || true); do
    crictl stop "${cid}" >/dev/null 2>&1 || true
    crictl rm "${cid}" >/dev/null 2>&1 || true
  done

  for pod_name in "${CRI_POD_NAME}" l8k; do
    for pod_id in $(crictl pods --name "${pod_name}" --quiet 2>/dev/null || true); do
      crictl stopp "${pod_id}" >/dev/null 2>&1 || true
      crictl rmp "${pod_id}" >/dev/null 2>&1 || true
    done
  done

  rm -f "${CRI_POD_UID_FILE}"
}

function collect_cluster_diagnostics() {
  configure_cluster_namespaces

  echo
  echo "Network Operator diagnostics:"
  echo
  echo "NicClusterPolicy:"
  kctl get nicclusterpolicy -A -o wide 2>/dev/null || true
  echo
  echo "NicNodePolicy:"
  kctl get nicnodepolicy -A -o wide 2>/dev/null || true
  echo
  echo "Network Operator pods (${NETWORK_OPERATOR_NAMESPACE}):"
  kctl get pods -n "${NETWORK_OPERATOR_NAMESPACE}" -o wide 2>/dev/null || true
  echo
  echo "Recent Network Operator events (${NETWORK_OPERATOR_NAMESPACE}):"
  kctl get events -n "${NETWORK_OPERATOR_NAMESPACE}" --sort-by=.lastTimestamp 2>/dev/null | tail -n 40 || true
}

function debug_discovery() {
  configure_cluster_namespaces

  echo "Launch Kit discovery debug"
  echo "script_version=${SCRIPT_VERSION}"
  echo "network_operator_namespace=${NETWORK_OPERATOR_NAMESPACE}"
  echo "launchkit_job=${K8S_JOB_NAMESPACE}/${K8S_JOB_NAME}"
  echo "discovery_namespace=${DISCOVERY_NAMESPACE}"
  echo "selector=${DISCOVERY_LABEL}"
  echo

  echo "Selected discovery nodes:"
  if [ "$#" -gt 0 ]; then
    for node in "$@"; do
      kctl get node "${node}" \
        -L "${DISCOVERY_LABEL_KEY}" \
        -L feature.node.kubernetes.io/pci-15b3.present \
        -o wide 2>/dev/null || true
    done
  else
    kctl get nodes -l "${DISCOVERY_LABEL}" \
      -L "${DISCOVERY_LABEL_KEY}" \
      -L feature.node.kubernetes.io/pci-15b3.present \
      -o wide 2>/dev/null || true
  fi

  echo
  echo "Launch Kit Job:"
  kctl -n "${K8S_JOB_NAMESPACE}" get job "${K8S_JOB_NAME}" -o wide 2>/dev/null || true
  kctl -n "${K8S_JOB_NAMESPACE}" get pods -l job-name="${K8S_JOB_NAME}" -o wide 2>/dev/null || true

  echo
  echo "Launch Kit Job logs:"
  local l8k_pods
  l8k_pods="$(kctl -n "${K8S_JOB_NAMESPACE}" get pods -l job-name="${K8S_JOB_NAME}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
  if [ -z "${l8k_pods}" ]; then
    echo "No Launch Kit job pod found."
  else
    for pod in ${l8k_pods}; do
      echo
      echo "--- logs ${K8S_JOB_NAMESPACE}/${pod}"
      kctl -n "${K8S_JOB_NAMESPACE}" logs "${pod}" --all-containers=true --tail=200 2>&1 || true
    done
  fi

  echo
  echo "NicClusterPolicy:"
  kctl get nicclusterpolicy -o wide 2>/dev/null || true
  kctl get nicclusterpolicy -o json 2>/dev/null | jq -r '
    .items[]
    | "name=\(.metadata.name) state=\(.status.state // "unknown")",
      ((.status.appliedStates // [])[]? | "  \(.name): \(.state)")
  ' 2>/dev/null || true

  echo
  echo "NicNodePolicy:"
  kctl get nicnodepolicy -A -o wide 2>/dev/null || true

  echo
  echo "Discovery namespace pods (${DISCOVERY_NAMESPACE}):"
  kctl -n "${DISCOVERY_NAMESPACE}" get pods -o wide 2>/dev/null || true

  echo
  echo "Discovery namespace daemonsets (${DISCOVERY_NAMESPACE}):"
  kctl -n "${DISCOVERY_NAMESPACE}" get daemonset -o wide 2>/dev/null || true

  if [ "$#" -gt 0 ]; then
    echo
    echo "Discovery namespace pods by requested node:"
    for node in "$@"; do
      echo
      echo "--- node ${node}"
      kctl -n "${DISCOVERY_NAMESPACE}" get pods --field-selector "spec.nodeName=${node}" -o wide 2>/dev/null || true
      if [ "${K8S_JOB_NAMESPACE}" != "${DISCOVERY_NAMESPACE}" ]; then
        kctl -n "${K8S_JOB_NAMESPACE}" get pods --field-selector "spec.nodeName=${node}" -o wide 2>/dev/null || true
      fi
    done
  fi

  echo
  echo "Likely discovery/NIC pod logs (${DISCOVERY_NAMESPACE}):"
  local pods
  pods="$(kctl -n "${DISCOVERY_NAMESPACE}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels}{"\n"}{end}' 2>/dev/null \
    | awk 'tolower($0) ~ /nic|discover|config|daemon|network/ {print $1}' || true)"
  if [ -z "${pods}" ]; then
    echo "No likely discovery pods found by name/labels."
  else
    for pod in ${pods}; do
      echo
      echo "--- describe ${DISCOVERY_NAMESPACE}/${pod}"
      kctl -n "${DISCOVERY_NAMESPACE}" describe pod "${pod}" 2>&1 | sed -n '1,180p' || true
      echo
      echo "--- logs ${DISCOVERY_NAMESPACE}/${pod}"
      kctl -n "${DISCOVERY_NAMESPACE}" logs "${pod}" --all-containers=true --tail=200 2>&1 || true
    done
  fi

  echo
  echo "Recent events (${DISCOVERY_NAMESPACE}):"
  kctl -n "${DISCOVERY_NAMESPACE}" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 80 || true

  echo
  echo "Recent events (${K8S_JOB_NAMESPACE}):"
  kctl -n "${K8S_JOB_NAMESPACE}" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n 80 || true
}

function exit_code_meaning() {
  case "${1:-}" in
    0) echo "success" ;;
    1) echo "generic application error" ;;
    2) echo "l8k/config/profile error" ;;
    3) echo "kubeconfig/client setup error" ;;
    124) echo "wrapper timeout" ;;
    137) echo "SIGKILL, often OOM kill or external runtime kill" ;;
    143) echo "SIGTERM, graceful/external termination or app self-termination" ;;
    "") echo "unknown" ;;
    *) echo "unknown/non-standard exit code" ;;
  esac
}

function latest_debug_dir() {
  find "${DEBUG_DIR}" -maxdepth 1 -type d -name 'l8k-failure-*' 2>/dev/null | sort | tail -n1
}

function show_latest_debug() {
  local debug_path
  debug_path="$(latest_debug_dir)"

  if [ -z "${debug_path}" ]; then
    echo "No l8k debug bundles found under ${DEBUG_DIR}"
    return 1
  fi

  echo "Latest debug bundle: ${debug_path}"
  echo
  [ -f "${debug_path}/summary.txt" ] && sed -n '1,120p' "${debug_path}/summary.txt"
  [ -f "${debug_path}/exit-analysis.txt" ] && {
    echo
    sed -n '1,160p' "${debug_path}/exit-analysis.txt"
  }
  [ -f "${debug_path}/container-status.txt" ] && {
    echo
    echo "Container status:"
    sed -n '1,160p' "${debug_path}/container-status.txt"
  }
  [ -s "${debug_path}/dmesg-oom-kill-tail.txt" ] && {
    echo
    echo "Possible OOM/SIGKILL messages:"
    tail -30 "${debug_path}/dmesg-oom-kill-tail.txt"
  }
  [ -s "${debug_path}/journalctl-kill-signals.txt" ] && {
    echo
    echo "Recent journal kill/error messages:"
    tail -30 "${debug_path}/journalctl-kill-signals.txt"
  }
  [ -f "${debug_path}.tar.gz" ] && {
    echo
    echo "Archive: ${debug_path}.tar.gz"
  }
}

function collect_runtime_failure_debug() {
  local cid="${1:-}"
  local exit_code="${2:-unknown}"
  local debug_stamp
  local debug_path

  configure_cluster_namespaces

  debug_stamp="$(date +%Y%m%d-%H%M%S)"
  debug_path="${DEBUG_DIR}/l8k-failure-${debug_stamp}"
  mkdir -p "${debug_path}"

  echo
  echo "Collecting l8k failure debug bundle: ${debug_path}"

  {
    echo "script_version=${SCRIPT_VERSION}"
    echo "timestamp=$(date -Is)"
    echo "image=${IMAGE}"
    echo "exit_code=${exit_code}"
    echo "exit_meaning=$(exit_code_meaning "${exit_code}")"
    echo "container_id=${cid}"
    echo "workdir=${WORKDIR}"
    echo "network_operator_release=${NETWORK_OPERATOR_RELEASE}"
  } >"${debug_path}/summary.txt"

  cp "${CONTAINER_JSON}" "${debug_path}/l8k-container.json" 2>/dev/null || true
  cp "${POD_JSON}" "${debug_path}/l8k-pod.json" 2>/dev/null || true
  cp "${LAST_LOG}" "${debug_path}/l8k-last.log" 2>/dev/null || true
  cp "${LAST_INSPECT}" "${debug_path}/l8k-last-container-inspect.json" 2>/dev/null || true
  copy_cri_log_to "${debug_path}/cri-l8k.log"
  cp "${WORKDIR}/cluster-config.yaml" "${debug_path}/cluster-config.yaml" 2>/dev/null || true
  cp "${L8K_BASE_CONFIG}" "${debug_path}/l8k-config.yaml" 2>/dev/null || true
  cp "${NCP_BACKUP_FILE}" "${debug_path}/nicclusterpolicy-before-active-discovery.json" 2>/dev/null || true

  if [ -n "${cid}" ]; then
    crictl inspect "${cid}" >"${debug_path}/crictl-inspect-container.json" 2>&1 || true
    crictl inspectp "$(get_pod)" >"${debug_path}/crictl-inspect-pod.json" 2>&1 || true
    jq -r '
      "id: \(.status.id // "")",
      "state: \(.status.state // "")",
      "exitCode: \(.status.exitCode // "")",
      "reason: \(.status.reason // "")",
      "message: \(.status.message // "")",
      "createdAt: \(.status.createdAt // "")",
      "startedAt: \(.status.startedAt // "")",
      "finishedAt: \(.status.finishedAt // "")",
      "imageRef: \(.status.imageRef // "")",
      "logPath: \(.status.logPath // "")"
    ' "${debug_path}/crictl-inspect-container.json" >"${debug_path}/container-status.txt" 2>&1 || true
  fi

  crictl ps -a >"${debug_path}/crictl-ps-a.txt" 2>&1 || true
  crictl pods >"${debug_path}/crictl-pods.txt" 2>&1 || true
  crictl images >"${debug_path}/crictl-images.txt" 2>&1 || true
  crictl stats >"${debug_path}/crictl-stats.txt" 2>&1 || true

  kctl get nicclusterpolicy -o yaml >"${debug_path}/nicclusterpolicy-live.yaml" 2>&1 || true
  kctl get nicclusterpolicy -o json >"${debug_path}/nicclusterpolicy-live.json" 2>&1 || true
  kctl get nicnodepolicy -A -o yaml >"${debug_path}/nicnodepolicy-live.yaml" 2>&1 || true
  kctl get pods -n "${NETWORK_OPERATOR_NAMESPACE}" -o wide >"${debug_path}/network-operator-pods.txt" 2>&1 || true
  kctl get events -n "${NETWORK_OPERATOR_NAMESPACE}" --sort-by=.lastTimestamp >"${debug_path}/network-operator-events.txt" 2>&1 || true
  kctl get nodes -o wide >"${debug_path}/nodes.txt" 2>&1 || true

  if command -v dmesg >/dev/null 2>&1; then
    dmesg -T >"${debug_path}/dmesg.txt" 2>&1 || true
    dmesg -T | egrep -i 'killed process|out of memory|oom|memory cgroup|l8k|launch|containerd|runc' | tail -100 >"${debug_path}/dmesg-oom-kill-tail.txt" 2>&1 || true
  fi

  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u containerd --since "30 minutes ago" >"${debug_path}/journalctl-containerd.txt" 2>&1 || true
    journalctl --since "30 minutes ago" | egrep -i 'oom|out of memory|killed|sigkill|containerd|runc|l8k|launch' >"${debug_path}/journalctl-kill-signals.txt" 2>&1 || true
  fi

  free -h >"${debug_path}/free-h.txt" 2>&1 || true
  df -h >"${debug_path}/df-h.txt" 2>&1 || true
  mount >"${debug_path}/mount.txt" 2>&1 || true
  cat /proc/meminfo >"${debug_path}/proc-meminfo.txt" 2>&1 || true

  {
    echo "Exit code: ${exit_code}"
    echo "Meaning: $(exit_code_meaning "${exit_code}")"
    echo
    echo "Cluster config:"
    if [ -s "${WORKDIR}/cluster-config.yaml" ]; then
      ls -l "${WORKDIR}/cluster-config.yaml"
    else
      echo "cluster-config.yaml missing or empty"
    fi
    echo
    echo "NCP backup file:"
    if [ -s "${NCP_BACKUP_FILE}" ]; then
      ls -l "${NCP_BACKUP_FILE}"
    else
      echo "NCP backup missing"
    fi
    echo
    echo "NCP live vs backup:"
    if [ -s "${NCP_BACKUP_FILE}" ] && [ -s "${debug_path}/nicclusterpolicy-live.json" ]; then
      jq '.items[].spec' "${NCP_BACKUP_FILE}" >"${debug_path}/ncp-backup-spec.json" 2>/dev/null || true
      jq '.items[].spec' "${debug_path}/nicclusterpolicy-live.json" >"${debug_path}/ncp-live-spec.json" 2>/dev/null || true
      diff -u "${debug_path}/ncp-backup-spec.json" "${debug_path}/ncp-live-spec.json" || true
    else
      echo "NCP diff unavailable"
    fi
  } >"${debug_path}/exit-analysis.txt" 2>&1

  tar -czf "${debug_path}.tar.gz" -C "${DEBUG_DIR}" "$(basename "${debug_path}")" 2>/dev/null || true

  echo "Failure debug bundle directory: ${debug_path}"
  if [ -f "${debug_path}.tar.gz" ]; then
    echo "Failure debug bundle archive: ${debug_path}.tar.gz"
  fi
  echo
  echo "Most relevant quick checks:"
  sed -n '1,80p' "${debug_path}/summary.txt" 2>/dev/null || true
  if [ -f "${debug_path}/exit-analysis.txt" ]; then
    echo
    sed -n '1,120p' "${debug_path}/exit-analysis.txt" || true
  fi
  if [ -f "${debug_path}/container-status.txt" ]; then
    echo
    echo "Container status:"
    sed -n '1,80p' "${debug_path}/container-status.txt" || true
  fi
  if [ -s "${debug_path}/dmesg-oom-kill-tail.txt" ]; then
    echo
    echo "Possible OOM/SIGKILL messages:"
    tail -30 "${debug_path}/dmesg-oom-kill-tail.txt" || true
  fi
  if [ -s "${debug_path}/journalctl-kill-signals.txt" ]; then
    echo
    echo "Recent journal kill/error messages:"
    tail -30 "${debug_path}/journalctl-kill-signals.txt" || true
  fi
}

function backup_nicclusterpolicy() {
  mkdir -p "${NCP_BACKUP_DIR}"
  echo
  echo "Backing up current NicClusterPolicy to ${NCP_BACKUP_FILE}"

  if kctl get nicclusterpolicy -o json >"${NCP_BACKUP_FILE}" 2>/dev/null; then
    local count
    count="$(jq -r '.items | length' "${NCP_BACKUP_FILE}")"
    echo "Backed up ${count} NicClusterPolicy object(s)."
    sanitize_nicclusterpolicy_backup
  else
    cat >"${NCP_BACKUP_FILE}" <<'EOF'
{
  "apiVersion": "v1",
  "kind": "List",
  "items": []
}
EOF
    echo "No NicClusterPolicy objects found to back up."
  fi
}

function sanitize_nicclusterpolicy_backup() {
  local sanitized_file
  sanitized_file="${NCP_BACKUP_FILE}.sanitized"

  jq '
    .items |= map(
      if (
        (.spec.nicConfigurationOperator? != null) and
        ((.spec.nicConfigurationOperator.operator.repository // "") == "nvcr.io/nvidia/mellanox") and
        ((.spec.nicConfigurationOperator.operator.version // "") == "network-operator-v26.4.0") and
        ((.spec.nicConfigurationOperator.configurationDaemon.repository // "") == "nvcr.io/nvidia/mellanox") and
        ((.spec.nicConfigurationOperator.configurationDaemon.version // "") == "network-operator-v26.4.0")
      )
      then
        .metadata.annotations["network.nvidia.com/l8k-sanitized-backup"] = "removed-invalid-ga-nicConfigurationOperator" |
        del(.spec.nicConfigurationOperator)
      else
        .
      end
    )
  ' "${NCP_BACKUP_FILE}" >"${sanitized_file}"

  if ! cmp -s "${NCP_BACKUP_FILE}" "${sanitized_file}"; then
    echo "Sanitized backup: removed invalid GA nicConfigurationOperator network-operator-v26.4.0 stanza."
    mv "${sanitized_file}" "${NCP_BACKUP_FILE}"
  else
    rm -f "${sanitized_file}"
  fi
}

function restore_nicclusterpolicy() {
  if [ ! -s "${NCP_BACKUP_FILE}" ]; then
    echo "No NicClusterPolicy backup found at ${NCP_BACKUP_FILE}; skipping restore."
    return
  fi

  local count
  count="$(jq -r '.items | length' "${NCP_BACKUP_FILE}")"

  echo
  echo "Restoring NicClusterPolicy from ${NCP_BACKUP_FILE}"

  if [ "${count}" = "0" ]; then
    for name in $(kctl get nicclusterpolicy -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true); do
      echo "Deleting NicClusterPolicy created during active discovery: ${name}"
      kctl delete nicclusterpolicy "${name}" --ignore-not-found=true >/dev/null
    done
    return
  fi

  jq '
    .items |= map(
      del(
        .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"],
        .metadata.creationTimestamp,
        .metadata.generation,
        .metadata.managedFields,
        .metadata.resourceVersion,
        .metadata.uid,
        .status
      )
    )
  ' "${NCP_BACKUP_FILE}" >"${NCP_RESTORE_FILE}"

  kctl apply -f "${NCP_RESTORE_FILE}"
  echo "NicClusterPolicy restore complete."
}

function repair_nicclusterpolicy_from_backup() {
  if [ ! -s "${NCP_BACKUP_FILE}" ]; then
    echo "No NicClusterPolicy backup found at ${NCP_BACKUP_FILE}; cannot repair."
    exit 1
  fi

  local count
  count="$(jq -r '.items | length' "${NCP_BACKUP_FILE}")"

  if [ "${count}" = "0" ]; then
    echo "Backup contains no NicClusterPolicy objects; removing any live NicClusterPolicy objects."
    for name in $(kctl get nicclusterpolicy -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true); do
      echo "Deleting live NicClusterPolicy: ${name}"
      kctl delete nicclusterpolicy "${name}" --ignore-not-found=true >/dev/null
    done
    return
  fi

  jq -r '.items[].metadata.name' "${NCP_BACKUP_FILE}" | while read -r name; do
    [ -n "${name}" ] || continue

    if jq -e --arg name "${name}" '.items[] | select(.metadata.name == $name) | .spec | has("nicConfigurationOperator")' "${NCP_BACKUP_FILE}" >/dev/null; then
      local section_file
      section_file="${NCP_BACKUP_DIR}/${name}-nic-configuration-operator.json"
      jq --arg name "${name}" '.items[] | select(.metadata.name == $name) | .spec.nicConfigurationOperator' "${NCP_BACKUP_FILE}" >"${section_file}"
      echo "Restoring spec.nicConfigurationOperator on ${name} from backup."
      kctl patch nicclusterpolicy "${name}" --type merge --patch-file <(
        jq -n --slurpfile section "${section_file}" '{spec: {nicConfigurationOperator: $section[0]}}'
      )
    else
      echo "Backup had no spec.nicConfigurationOperator for ${name}; removing live section if present."
      kctl patch nicclusterpolicy "${name}" --type json -p='[{"op":"remove","path":"/spec/nicConfigurationOperator"}]' >/dev/null 2>&1 || true
    fi
  done
}

function patch_valid_nicconfigurationoperator() {
  local mode="${1:-verbose}"

  if [ "${mode}" != "quiet" ]; then
    echo
    echo "Patching NicClusterPolicy with valid NIC Configuration Operator image paths for beta discovery."
    echo "repository=${NCO_REPOSITORY}"
    echo "version=${NCO_VERSION}"
    echo "imagePullSecret=${NCO_IMAGE_PULL_SECRET}"
  fi

  local names
  names="$(kctl get nicclusterpolicy -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"

  if [ -z "${names}" ]; then
    if [ "${mode}" != "quiet" ]; then
      echo "No live NicClusterPolicy found to patch."
    fi
    return
  fi

  for name in ${names}; do
    if [ "${mode}" != "quiet" ]; then
      echo "Patching NicClusterPolicy ${name}"
    fi

    local patch_json
    patch_json="$(cat <<EOF
{
  "spec": {
    "nicConfigurationOperator": {
      "operator": {
        "image": "nic-configuration-operator",
        "repository": "${NCO_REPOSITORY}",
        "version": "${NCO_VERSION}",
        "imagePullSecrets": ["${NCO_IMAGE_PULL_SECRET}"]
      },
      "configurationDaemon": {
        "image": "nic-configuration-operator-daemon",
        "repository": "${NCO_REPOSITORY}",
        "version": "${NCO_VERSION}",
        "imagePullSecrets": ["${NCO_IMAGE_PULL_SECRET}"]
      },
      "logLevel": "info"
    }
  }
}
EOF
)"

    if [ "${mode}" = "quiet" ]; then
      kctl patch nicclusterpolicy "${name}" --type merge -p "${patch_json}" >/dev/null 2>&1 || true
    else
      kctl patch nicclusterpolicy "${name}" --type merge -p "${patch_json}"
    fi
  done
}

function start_nco_patch_guard() {
  rm -f "${NCO_PATCH_GUARD_STOP_FILE}" "${NCO_PATCH_GUARD_PID_FILE}"
  echo "Starting beta NCO image guard while Launch Kit discovery runs."

  (
    rapid_count=0
    while [ ! -f "${NCO_PATCH_GUARD_STOP_FILE}" ]; do
      patch_valid_nicconfigurationoperator quiet
      rapid_count=$((rapid_count + 1))
      if [ "${rapid_count}" -lt 40 ]; then
        sleep 0.05
      else
        sleep 2
      fi
    done
  ) &

  echo "$!" >"${NCO_PATCH_GUARD_PID_FILE}"
}

function stop_nco_patch_guard() {
  local pid
  touch "${NCO_PATCH_GUARD_STOP_FILE}"

  if [ -f "${NCO_PATCH_GUARD_PID_FILE}" ]; then
    pid="$(cat "${NCO_PATCH_GUARD_PID_FILE}")"
    if [ -n "${pid}" ]; then
      wait "${pid}" 2>/dev/null || true
    fi
  fi

  rm -f "${NCO_PATCH_GUARD_STOP_FILE}" "${NCO_PATCH_GUARD_PID_FILE}"
}

function run_l8k_with_nco_guard() {
  local status

  patch_valid_nicconfigurationoperator
  start_nco_patch_guard

  set +e
  L8K_COLLECT_CLUSTER_DIAGNOSTICS=true run_l8k "$@"
  status=$?

  stop_nco_patch_guard
  return "${status}"
}

function run_with_ncp_restore() {
  local status
  backup_nicclusterpolicy
  set +e
  "$@"
  status=$?
  restore_nicclusterpolicy
  repair_nicclusterpolicy_from_backup
  set -e
  return "${status}"
}

function worker_nodes() {
  kctl get nodes -o json | jq -r '
    .items[]
    | select((.metadata.labels["node-role.kubernetes.io/control-plane"] // "") == "")
    | select((.metadata.labels["node-role.kubernetes.io/master"] // "") == "")
    | .metadata.name
  '
}

function show_workers() {
  echo "Worker nodes:"
  worker_nodes
}

function show_default_discovery_nodes() {
  echo "Nodes matching Launch Kit default selector: ${DEFAULT_NODE_SELECTOR}"
  kctl get nodes -l "${DEFAULT_NODE_SELECTOR}" \
    -L feature.node.kubernetes.io/pci-15b3.present \
    -L "${DISCOVERY_LABEL_KEY}"
}

function show_labeled_discovery_nodes() {
  echo "Nodes matching explicit Launch Kit training selector: ${DISCOVERY_LABEL}"
  kctl get nodes -l "${DISCOVERY_LABEL}" \
    -L "${DISCOVERY_LABEL_KEY}" \
    -L feature.node.kubernetes.io/pci-15b3.present
}

function clear_discovery_labels() {
  local nodes
  nodes="$(kctl get nodes -l "${DISCOVERY_LABEL}" -o name 2>/dev/null | sed 's#node/##' || true)"

  if [ -z "${nodes}" ]; then
    echo "No existing ${DISCOVERY_LABEL_KEY} labels found"
    return
  fi

  for node in ${nodes}; do
    echo "Removing ${DISCOVERY_LABEL_KEY} from ${node}"
    kctl label node "${node}" "${DISCOVERY_LABEL_KEY}-" --overwrite >/dev/null
  done
}

function label_discovery_nodes() {
  if [ "$#" -eq 0 ]; then
    set -- $(worker_nodes)
  fi

  if [ "$#" -eq 0 ]; then
    echo "No worker nodes found. Pass one or more explicit node names."
    exit 1
  fi

  for node in "$@"; do
    echo "Labeling ${node} with ${DISCOVERY_LABEL}"
    kctl label node "${node}" "${DISCOVERY_LABEL}" --overwrite >/dev/null
  done

  echo
  show_labeled_discovery_nodes
}

function active_discover_config() {
  show_default_discovery_nodes
  run_l8k_with_nco_guard \
    --user-config "${CONTAINER_L8K_BASE_CONFIG}" \
    --kubeconfig "${CONTAINER_KUBECONFIG}" \
    --discover-cluster-config \
    --node-selector "${DEFAULT_NODE_SELECTOR}" \
    --save-cluster-config /work/cluster-config.yaml \
    --network-operator-release "${NETWORK_OPERATOR_RELEASE}" \
    --log-level debug \
    --yes
}

function active_discover_labeled_config() {
  show_labeled_discovery_nodes
  run_l8k_with_nco_guard \
    --user-config "${CONTAINER_L8K_BASE_CONFIG}" \
    --kubeconfig "${CONTAINER_KUBECONFIG}" \
    --discover-cluster-config \
    --node-selector "${DISCOVERY_LABEL}" \
    --save-cluster-config /work/cluster-config.yaml \
    --network-operator-release "${NETWORK_OPERATOR_RELEASE}" \
    --log-level debug \
    --output text \
    --yes
}

function active_discover_node_config() {
  if [ "$#" -eq 0 ]; then
    echo "usage: $0 active-discover-node-config <node-name> [node-name ...]"
    exit 1
  fi

  clear_discovery_labels
  label_discovery_nodes "$@"
  active_discover_labeled_config
}

function verify_cluster_config() {
  local config_path="${WORKDIR}/cluster-config.yaml"

  if [ ! -s "${config_path}" ]; then
    echo "Missing or empty cluster config: ${config_path}"
    exit 1
  fi

  echo
  echo "Verified cluster config: ${config_path}"
  ls -l "${config_path}"
}

function verify_base_config() {
  if [ ! -s "${L8K_BASE_CONFIG}" ]; then
    echo "Missing or empty base config: ${L8K_BASE_CONFIG}"
    exit 1
  fi

  echo
  echo "Using existing Launch Kit base config: ${L8K_BASE_CONFIG}"
  ls -l "${L8K_BASE_CONFIG}"
}

function generate_sriov() {
  run_l8k \
    --user-config "${CONTAINER_L8K_BASE_CONFIG}" \
    --fabric ethernet \
    --deployment-type sriov \
    --multirail \
    --network-operator-release "${NETWORK_OPERATOR_RELEASE}" \
    --save-deployment-files /work/deployment \
    --yes
}

function preview_sriov() {
  run_l8k \
    --user-config "${CONTAINER_L8K_BASE_CONFIG}" \
    --fabric ethernet \
    --deployment-type sriov \
    --multirail \
    --network-operator-release "${NETWORK_OPERATOR_RELEASE}" \
    --save-deployment-files /work/deployment \
    --dry-run \
    --output text \
    --yes
}

function show_deployment() {
  local deployment_dir="${WORKDIR}/deployment"

  if [ ! -d "${deployment_dir}" ]; then
    echo "Deployment directory was not created: ${deployment_dir}"
    exit 1
  fi

  echo
  echo "Generated deployment files:"
  find "${deployment_dir}" -maxdepth 5 -type f | sort
}

function sanitize_k8s_name() {
  echo "$1" \
    | tr '[:upper:]_' '[:lower:]-' \
    | sed -E 's/[^a-z0-9.-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' \
    | cut -c1-50
}

function generate_live_sriov_rdma_networks() {
  if [ "$#" -eq 0 ]; then
    echo "usage: $0 live-sriov-rdma-networks <node-name> [node-name ...]"
    exit 1
  fi

  configure_cluster_namespaces

  local outdir="${WORKDIR}/discovered-sriov-rdma"
  local node_json_dir="${outdir}/nodes"
  local policies_json="${outdir}/sriovnetworknodepolicies.json"
  local resources_file="${outdir}/resources.txt"
  local node_resources_file="${outdir}/node-resources.txt"
  local networks_yaml="${outdir}/sriov-rdma-networks.yaml"

  mkdir -p "${outdir}" "${node_json_dir}"
  : >"${resources_file}"
  : >"${node_resources_file}"

  echo
  echo "Building SR-IOV/RDMA network definitions from live Kubernetes state."
  echo "Nodes: $*"
  echo "Output directory: ${outdir}"

  if kctl get sriovnetworknodepolicy -A -o json >"${policies_json}" 2>/dev/null; then
    jq -r '
      .items[]
      | select((.spec.isRdma == true) or ((.spec.resourceName // "") | test("rdma|sriov|mlx|mlnx"; "i")))
      | .spec.resourceName // empty
    ' "${policies_json}" >>"${resources_file}" || true
  else
    echo '{"apiVersion":"v1","items":[]}' >"${policies_json}"
  fi

  for node in "$@"; do
    local node_file
    node_file="${node_json_dir}/${node}.json"

    if ! kctl get node "${node}" -o json >"${node_file}" 2>/dev/null; then
      echo "WARNING: could not read node ${node}; skipping node resource discovery."
      continue
    fi

    jq -r --arg node "${node}" '
      (.status.allocatable // {})
      | to_entries[]
      | select(.key | test("rdma|sriov|mlx|mlnx"; "i"))
      | [$node, .key, .value] | @tsv
    ' "${node_file}" >>"${node_resources_file}" || true

    jq -r '
      (.status.allocatable // {})
      | keys[]
      | select(test("rdma|sriov|mlx|mlnx"; "i"))
      | split("/")[-1]
    ' "${node_file}" >>"${resources_file}" || true
  done

  sort -u "${resources_file}" -o "${resources_file}"

  if [ ! -s "${resources_file}" ]; then
    echo "No SR-IOV/RDMA allocatable resources or RDMA SriovNetworkNodePolicy resourceNames were found."
    echo "Captured policies: ${policies_json}"
    echo "Captured node resources: ${node_resources_file}"
    return 1
  fi

  {
    echo "# Generated by launchkit.sh ${SCRIPT_VERSION}"
    echo "# Source: live Kubernetes node allocatable resources and SriovNetworkNodePolicy objects"
    echo "# Nodes: $*"
  } >"${networks_yaml}"

  while read -r resource_name; do
    [ -n "${resource_name}" ] || continue

    local safe_name
    local pool_name
    safe_name="$(sanitize_k8s_name "${resource_name}")"
    pool_name="sriovnet-pool-${safe_name}"

    cat >>"${networks_yaml}" <<EOF
---
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: "sriov-rdma-${safe_name}"
  namespace: ${NETWORK_OPERATOR_NAMESPACE}
spec:
  vlan: 0
  networkNamespace: "default"
  resourceName: "${resource_name}"
  ipam: |
    {
      "type": "nv-ipam",
      "datastore": "kubernetes",
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/nv-ipam.d/nv-ipam.kubeconfig"
      },
      "log_file": "/var/log/SriovNetwork_nv-ipam.log",
      "log_level": "debug",
      "poolName": "${pool_name}",
      "poolType": "IPPool"
    }
EOF
  done <"${resources_file}"

  echo
  echo "Live SR-IOV/RDMA resources by node:"
  if [ -s "${node_resources_file}" ]; then
    column -t -s $'\t' "${node_resources_file}" 2>/dev/null || cat "${node_resources_file}"
  else
    echo "No matching node allocatable resources found; using SriovNetworkNodePolicy resourceNames only."
  fi

  echo
  echo "Generated SR-IOV/RDMA SriovNetwork definitions:"
  echo "${networks_yaml}"
  sed -n '1,260p' "${networks_yaml}"
}

function show_rdmadev_sriov_networks() {
  if [ "$#" -eq 0 ]; then
    echo "usage: $0 show-rdma-sriov-networks <node-name> [node-name ...]"
    exit 1
  fi

  echo
  echo "RDMA/SR-IOV discovery and generated network definitions for nodes: $*"

  if [ ! -s "${WORKDIR}/cluster-config.yaml" ]; then
    echo
    echo "cluster-config.yaml is missing or empty; using live Kubernetes SR-IOV/RDMA fallback."
    generate_live_sriov_rdma_networks "$@"
    return
  fi

  for node in "$@"; do
    echo
    echo "────────────────────────────────────────"
    echo "Node: ${node}"
    echo "────────────────────────────────────────"

    echo
    echo "Discovered RDMA/SR-IOV entries from cluster-config.yaml:"
    if command -v yq >/dev/null 2>&1; then
      yq eval --arg node "${node}" '
        .. |
        select(tag == "!!map") |
        select(
          (.node == $node) or
          (.nodeName == $node) or
          (.name == $node) or
          (.hostname == $node) or
          (.workerNode == $node) or
          (.workerNodes[]? == $node) or
          (.nodes[]? == $node)
        )
      ' "${WORKDIR}/cluster-config.yaml" || true
    else
      awk -v node="${node}" '
        $0 ~ node {show=1; before=8; after=45}
        show && before > 0 {print; before--; next}
        show && after > 0 {print; after--; next}
        after == 0 {show=0}
      ' "${WORKDIR}/cluster-config.yaml" || true
    fi

    echo
    echo "Generated SR-IOV network YAML referencing this node or SR-IOV/RDMA resources:"
    if [ -d "${WORKDIR}/deployment" ]; then
      local matched=0
      while IFS= read -r file; do
        if grep -Eiq "${node}|SriovNetwork|SriovIBNetwork|SriovNetworkNodePolicy|resourceName|rdma|sriov|mlx5|pfNames|rootDevices" "${file}"; then
          matched=1
          echo
          echo "--- ${file}"
          sed -n '1,240p' "${file}"
        fi
      done < <(find "${WORKDIR}/deployment" -maxdepth 6 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)

      if [ "${matched}" -eq 0 ]; then
        echo "No generated SR-IOV/RDMA YAML found under ${WORKDIR}/deployment."
      fi
    else
      echo "No deployment directory found at ${WORKDIR}/deployment. Run generate-sriov after active discovery creates cluster-config.yaml."
    fi

    echo
    echo "Profile templates used for SR-IOV Ethernet RDMA:"
    if [ -d "${WORKDIR}/profiles/sriov-ethernet-rdma" ]; then
      find "${WORKDIR}/profiles/sriov-ethernet-rdma" -maxdepth 1 -type f | sort
    else
      echo "Profile directory not staged: ${WORKDIR}/profiles/sriov-ethernet-rdma"
    fi
  done
}

function lab_sriov_generate_preview() {
  if [ "$#" -gt 0 ]; then
    echo "Labeling selected nodes for operator visibility only; no Launch Kit discovery will run: $*"
    clear_discovery_labels
    label_discovery_nodes "$@"
  else
    echo "No nodes supplied; generating from existing Launch Kit base config only."
  fi

  echo
  echo "NOTE: Offline generation requires ${L8K_BASE_CONFIG} to contain a complete clusterConfig."
  echo "      This command does not infer PCI addresses, RDMA devices, PF names, or rails."

  echo
  echo "Step 1: verify existing base config"
  ensure_l8k_config
  verify_base_config
  ensure_l8k_assets
  verify_profile_assets

  echo
  echo "Step 2: generate SR-IOV deployment YAML without changing the cluster"
  generate_sriov

  echo
  echo "Step 3: preview deployment without applying changes"
  preview_sriov

  echo
  echo "Step 4: show generated deployment"
  show_deployment
}

function lab_sriov_active_discovery() {
  if [ "$#" -eq 0 ]; then
    echo "usage: $0 lab-sriov <node-name> [node-name ...]"
    exit 1
  fi

  echo "Preparing SR-IOV Launch Kit lab for nodes: $*"

  echo
  echo "Step 1: clear old discovery labels"
  clear_discovery_labels

  echo
  echo "Step 2: label selected nodes"
  label_discovery_nodes "$@"

  echo
  echo "Step 3: actively discover labeled nodes; this can patch the running NicClusterPolicy"
  active_discover_labeled_config

  echo
  echo "Step 4: verify cluster config"
  verify_cluster_config

  echo
  echo "Step 5: generate SR-IOV deployment YAML"
  generate_sriov

  echo
  echo "Step 6: show generated deployment"
  show_deployment
}

function active_discover_generate_show() {
  if [ "$#" -eq 0 ]; then
    echo "usage: $0 active-discover-generate-show <node-name> [node-name ...]"
    exit 1
  fi

  local discovery_status=0

  echo "Step 1: active discovery for nodes with NicClusterPolicy backup/restore: $*"
  set +e
  run_with_ncp_restore active_discover_node_config "$@"
  discovery_status=$?
  set -e

  echo
  echo "Step 2: verify discovered cluster config"
  if [ "${discovery_status}" -ne 0 ] || [ ! -s "${WORKDIR}/cluster-config.yaml" ]; then
    echo "Launch Kit active discovery did not produce ${WORKDIR}/cluster-config.yaml."
    echo "Falling back to live Kubernetes SR-IOV/RDMA resource discovery."
    generate_live_sriov_rdma_networks "$@"
    return
  fi

  verify_cluster_config

  echo
  echo "Step 3: generate SR-IOV deployment YAML"
  ensure_l8k_config
  verify_base_config
  ensure_l8k_assets
  verify_profile_assets
  generate_sriov

  echo
  echo "Step 4: show discovered RDMA/SR-IOV network definitions"
  show_rdmadev_sriov_networks "$@"
}

function usage() {
  echo "usage: $0 {pull|start|stop|help|version|schema|workers|default-nodes|label-discovery|clear-discovery|diagnostics|debug-discovery|debug-last-failure|show-debug|profiles|repair-ncp-from-backup|active-discover-config|active-discover-node-config|active-discover-labeled-config|generate-sriov|preview-sriov|deploy-sriov|show-rdma-sriov-networks|live-sriov-rdma-networks|active-discover-generate-show|lab-sriov|lab-sriov-active-discovery|run -- <l8k args>}"
  echo
  echo "examples:"
  echo "  $0 pull"
  echo "  $0 default-nodes"
  echo "  $0 generate-sriov"
  echo "  $0 preview-sriov"
  echo "  $0 lab-sriov igx003 igx004          # offline generate/preview; requires complete clusterConfig"
  echo "  $0 workers"
  echo "  $0 label-discovery igx003 igx004"
  echo "  $0 active-discover-node-config igx003 igx004"
  echo "  $0 active-discover-labeled-config   # may patch running NicClusterPolicy to build clusterConfig"
  echo "  $0 show-rdma-sriov-networks igx003 igx004"
  echo "  $0 live-sriov-rdma-networks ovx001 igx003 igx004"
  echo "  $0 active-discover-generate-show igx003 igx004"
  echo "  $0 lab-sriov-active-discovery igx003 igx004"
  echo "  $0 repair-ncp-from-backup"
  echo "  $0 debug-discovery ovx001 igx003 igx004"
  echo "  $0 debug-last-failure"
  echo "  $0 show-debug"
}

case "${1:-}" in
  pull)
    endpoints
    pull_image
    ;;

  start)
    endpoints
    start_pod
    ;;

  stop)
    endpoints
    stop_all
    ;;

  help)
    run_l8k --help
    ;;

  version)
    run_l8k version
    ;;

  schema)
    run_l8k schema
    ;;

  workers)
    show_workers
    ;;

  default-nodes)
    show_default_discovery_nodes
    ;;

  label-discovery)
    shift
    label_discovery_nodes "$@"
    ;;

  clear-discovery)
    clear_discovery_labels
    ;;

  diagnostics)
    collect_cluster_diagnostics
    ;;

  debug-discovery)
    shift
    debug_discovery "$@"
    ;;

  debug-last-failure)
    collect_runtime_failure_debug "$(crictl ps -a --name l8k --quiet 2>/dev/null | head -n1 || true)" manual
    ;;

  show-debug)
    show_latest_debug
    ;;

  repair-ncp-from-backup)
    repair_nicclusterpolicy_from_backup
    ;;

  profiles)
    ensure_l8k_assets
    verify_profile_assets
    ;;

  discover|discover-node|discover-labeled|active-discover|active-discover-node|active-discover-labeled)
    echo "Command renamed to avoid hiding cluster mutation."
    echo "Use active-discover-config, active-discover-node-config, or active-discover-labeled-config."
    echo "These commands may patch the running NicClusterPolicy to build clusterConfig."
    exit 1
    ;;

  active-discover-config)
    echo "WARNING: active-discover-config may patch the running NicClusterPolicy to build clusterConfig."
    run_with_ncp_restore active_discover_config
    ;;

  active-discover-node-config)
    echo "WARNING: active-discover-node-config may patch the running NicClusterPolicy to build clusterConfig."
    shift
    run_with_ncp_restore active_discover_node_config "$@"
    ;;

  active-discover-labeled-config)
    echo "WARNING: active-discover-labeled-config may patch the running NicClusterPolicy to build clusterConfig."
    run_with_ncp_restore active_discover_labeled_config
    ;;

  generate-sriov)
    ensure_l8k_config
    verify_base_config
    ensure_l8k_assets
    verify_profile_assets
    generate_sriov
    ;;

  preview-sriov)
    ensure_l8k_config
    verify_base_config
    ensure_l8k_assets
    verify_profile_assets
    preview_sriov
    ;;

  deploy-sriov)
    L8K_COLLECT_CLUSTER_DIAGNOSTICS=true run_l8k \
      --kubeconfig "${CONTAINER_KUBECONFIG}" \
      --user-config "${CONTAINER_L8K_BASE_CONFIG}" \
      --fabric ethernet \
      --deployment-type sriov \
      --multirail \
      --network-operator-release "${NETWORK_OPERATOR_RELEASE}" \
      --save-deployment-files /work/deployment \
      --deploy \
      --yes
    ;;

  show-rdma-sriov-networks)
    shift
    show_rdmadev_sriov_networks "$@"
    ;;

  live-sriov-rdma-networks)
    shift
    generate_live_sriov_rdma_networks "$@"
    ;;

  active-discover-generate-show)
    shift
    echo "WARNING: active-discover-generate-show may patch the running NicClusterPolicy to build clusterConfig."
    active_discover_generate_show "$@"
    ;;

  lab-sriov)
    shift
    lab_sriov_generate_preview "$@"
    ;;

  lab-sriov-active-discovery)
    shift
    echo "WARNING: lab-sriov-active-discovery may patch the running NicClusterPolicy to build clusterConfig."
    run_with_ncp_restore lab_sriov_active_discovery "$@"
    ;;

  run)
    shift
    run_l8k "$@"
    ;;

  *)
    usage
    exit 1
    ;;
esac
