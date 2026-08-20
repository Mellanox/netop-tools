#!/bin/bash
set -euo pipefail

SYSCTL_CONFIG=${SYSCTL_CONFIG:-}
echo "SYSCTL_CONFIG:${SYSCTL_CONFIG}"

if [[ -z "${SYSCTL_CONFIG}" ]]; then
  exit 0
fi

is_allowed_sysctl_key() {
  case "$1" in
    net.ipv4.conf.all.rp_filter|\
    net.ipv4.conf.all.arp_announce|\
    net.ipv4.conf.all.arp_ignore)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

IFS=',' read -r -a SYSVALS <<< "${SYSCTL_CONFIG}"
for SYSVAL in "${SYSVALS[@]}"; do
  if [[ ! "${SYSVAL}" =~ ^([a-z0-9._]+)=([0-9]+)$ ]]; then
    echo "Invalid SYSCTL_CONFIG entry: ${SYSVAL}" >&2
    exit 1
  fi

  SYSCTL_KEY="${BASH_REMATCH[1]}"
  if ! is_allowed_sysctl_key "${SYSCTL_KEY}"; then
    echo "Disallowed SYSCTL_CONFIG key: ${SYSCTL_KEY}" >&2
    exit 1
  fi

  sysctl "${SYSVAL}"
done
