#!/bin/bash
#
# Regenerate containers/<VERSION> from network-operator's hack/release.yaml.
#
# containers/<VERSION> is a hand-curated CSV (display name, license, repository,
# image, release tag, mod tag, required Yes/No, notes) consumed by get_container()/
# get_repository()/get_release_tag() in ops/mk-*.sh. release.yaml only carries
# repository/version per component, so this script takes an existing curated
# containers/<TEMPLATE_VERSION> file as the source of truth for row order, display
# names, license, required flag, mod tag and notes, and refreshes only the
# repository/version columns from release.yaml. New components in release.yaml
# that have no row in the template are reported so a human can add them; template
# rows with no matching key in release.yaml are also reported and left unchanged.
#
# Usage:
#   ops/gen-containers-file.sh [-t TEMPLATE_VERSION] [-r RELEASE_YAML] [VERSION]
#
# VERSION defaults to release.yaml's NetworkOperator.version (v-prefix stripped).
# TEMPLATE_VERSION defaults to the newest containers/* file older than VERSION.
# RELEASE_YAML defaults to ~/network-operator/hack/release.yaml.
#
set -euo pipefail

if [ -z "${NETOP_ROOT_DIR:-}" ]; then
  echo "ERROR: NETOP_ROOT_DIR is not set" >&2
  exit 1
fi
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required" >&2; exit 1; }

CONTAINERS_DIR="${NETOP_ROOT_DIR}/containers"
RELEASE_YAML="${HOME}/network-operator/hack/release.yaml"
TEMPLATE_VERSION=""

while getopts ":t:r:" OPT; do
  case "${OPT}" in
  t) TEMPLATE_VERSION="${OPTARG}" ;;
  r) RELEASE_YAML="${OPTARG}" ;;
  *) echo "Usage: $0 [-t TEMPLATE_VERSION] [-r RELEASE_YAML] [VERSION]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

[ -r "${RELEASE_YAML}" ] || { echo "ERROR: release.yaml not found: ${RELEASE_YAML}" >&2; exit 1; }

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
  VERSION=$(yq -r '.NetworkOperator.version' "${RELEASE_YAML}")
  VERSION="${VERSION#v}"
fi

if [ -z "${TEMPLATE_VERSION}" ]; then
  TEMPLATE_VERSION=$(
    for F in "${CONTAINERS_DIR}"/*; do
      B=$(basename "${F}")
      [ "${B}" = "${VERSION}" ] && continue
      echo "${B}"
    done | sort -V | tail -1
  )
fi
TEMPLATE_FILE="${CONTAINERS_DIR}/${TEMPLATE_VERSION}"
[ -r "${TEMPLATE_FILE}" ] || { echo "ERROR: template containers file not found: ${TEMPLATE_FILE}" >&2; exit 1; }

OUT_FILE="${CONTAINERS_DIR}/${VERSION}"
echo "Generating ${OUT_FILE}" >&2
echo "  from template: ${TEMPLATE_FILE}" >&2
echo "  from release:  ${RELEASE_YAML}" >&2

# image (csv field 4) -> release.yaml top-level key. Stable across releases;
# extend this when a new component row is added to the template file.
declare -A IMAGE_TO_YAML_KEY=(
  [network-operator]="NetworkOperator"
  [network-operator-init-container]="NetworkOperatorInitContainer"
  [doca-driver]="Mofed"
  [doca-driver-stig-fips]="MofedStigFips"
  [k8s-rdma-shared-dev-plugin]="RdmaSharedDevicePlugin"
  [ib-kubernetes]="IbKubernetes"
  [ipoib-cni]="Ipoib"
  [nvidia-k8s-ipam]="nvIpam"
  [nic-feature-discovery]="nicFeatureDiscovery"
  [doca_telemetry]="docaTelemetryService"
  [node-feature-discovery]="nodeFeatureDiscovery"
  [sriov-network-operator]="SriovNetworkOperator"
  [sriov-network-operator-webhook]="SriovNetworkOperatorWebhook"
  [sriov-network-operator-config-daemon]="SriovConfigDaemon"
  [sriov-network-operator-config-daemon-stig-fips]="SriovConfigDaemonStigFips"
  [sriov-network-device-plugin]="SriovDevicePlugin"
  [sriov-cni]="SriovCni"
  [ib-sriov-cni]="SriovIbCni"
  [plugins]="CniPlugins"
  [multus-cni]="Multus"
  [rdma-cni]="rdmaCni"
  [ovs-cni-plugin]="ovsCni"
  [nic-configuration-operator]="nicConfigurationOperator"
  [nic-configuration-operator-daemon]="nicConfigurationConfigDaemon"
  [maintenance-operator]="maintenanceOperator"
  [spectrum-x-operator]="spectrumXOperator"
  [xplane]="xPlaneService"
  [k8s-launch-kit]="k8sLaunchKit"
  [dra-driver-sriov]="DraDriverSriov"
)
# image name is ambiguous for these (same image, different YAML keys); resolve by
# matching a substring of the template row's existing release-tag/version.
declare -A AMBIGUOUS_IMAGE_HINTS=(
  ["nic-configuration-operator-stig-fips|-rhel"]="nicConfigurationOperatorStigFipsRhel"
  ["nic-configuration-operator-stig-fips|-ubuntu"]="nicConfigurationOperatorStigFipsUbuntu"
  ["nic-configuration-operator-daemon-stig-fips|-rhel"]="nicConfigurationConfigDaemonStigFipsRhel"
  ["nic-configuration-operator-daemon-stig-fips|-ubuntu"]="nicConfigurationConfigDaemonStigFipsUbuntu"
  ["spectrum-x-operator-stig-fips|-rhel"]="spectrumXOperatorStigFipsRhel"
  ["spectrum-x-operator-stig-fips|-ubuntu"]="spectrumXOperatorStigFipsUbuntu"
)

resolve_yaml_key() {
  local IMAGE="$1" OLD_TAG="$2" KEY HINT_KEY

  if [ -n "${IMAGE_TO_YAML_KEY[${IMAGE}]+x}" ]; then
    echo "${IMAGE_TO_YAML_KEY[${IMAGE}]}"
    return 0
  fi
  for HINT_KEY in "${!AMBIGUOUS_IMAGE_HINTS[@]}"; do
    local HINT_IMAGE="${HINT_KEY%%|*}"
    local HINT_SUBSTR="${HINT_KEY#*|}"
    if [ "${HINT_IMAGE}" = "${IMAGE}" ] && { [ -z "${HINT_SUBSTR}" ] || [[ "${OLD_TAG}" == *"${HINT_SUBSTR}"* ]]; }; then
      echo "${AMBIGUOUS_IMAGE_HINTS[${HINT_KEY}]}"
      return 0
    fi
  done
  return 1
}

: > "${OUT_FILE}.tmp"
UNMATCHED_ROWS=0
while IFS=, read -r DISPLAY LICENSE OLD_REPO IMAGE OLD_TAG MOD_TAG REQUIRED NOTES; do
  [ -z "${IMAGE}" ] && continue
  if YAML_KEY=$(resolve_yaml_key "${IMAGE}" "${OLD_TAG}"); then
    REPO=$(yq -r ".${YAML_KEY}.repository // \"\"" "${RELEASE_YAML}")
    TAG=$(yq -r ".${YAML_KEY}.version // \"\"" "${RELEASE_YAML}")
    if [ -z "${REPO}" ] || [ -z "${TAG}" ]; then
      echo "WARNING: ${YAML_KEY} (image ${IMAGE}) missing repository/version in ${RELEASE_YAML}; keeping template values" >&2
      REPO="${OLD_REPO}"
      TAG="${OLD_TAG}"
    fi
  else
    echo "WARNING: no release.yaml mapping for image '${IMAGE}' (row: ${DISPLAY}); keeping template values unrefreshed" >&2
    REPO="${OLD_REPO}"
    TAG="${OLD_TAG}"
    UNMATCHED_ROWS=$((UNMATCHED_ROWS + 1))
  fi
  echo "${DISPLAY},${LICENSE},${REPO},${IMAGE},${TAG},${MOD_TAG},${REQUIRED},${NOTES}" >> "${OUT_FILE}.tmp"
done < "${TEMPLATE_FILE}"

# Report release.yaml components that have no row at all in the template.
mapfile -t TEMPLATE_YAML_KEYS < <(printf '%s\n' "${IMAGE_TO_YAML_KEY[@]}" "${AMBIGUOUS_IMAGE_HINTS[@]}" | sort -u)
mapfile -t RELEASE_YAML_KEYS < <(yq -r 'keys | .[]' "${RELEASE_YAML}" | sort -u)
for KEY in "${RELEASE_YAML_KEYS[@]}"; do
  if ! printf '%s\n' "${TEMPLATE_YAML_KEYS[@]}" | grep -qxF "${KEY}"; then
    echo "NOTE: release.yaml has component '${KEY}' with no row in ${TEMPLATE_FILE} (not added; add manually if it should ship)" >&2
  fi
done

mv "${OUT_FILE}.tmp" "${OUT_FILE}"
echo "Wrote ${OUT_FILE}" >&2
if [ "${UNMATCHED_ROWS}" -gt 0 ]; then
  echo "WARNING: ${UNMATCHED_ROWS} template row(s) could not be refreshed from release.yaml (see warnings above)" >&2
fi
