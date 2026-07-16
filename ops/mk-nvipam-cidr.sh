#!/bin/bash
#
# define nvipam CIDRPool resource - writes to stdout
# Args: IPPOOL_NAME NETWORK_RANGE GATEWAY_INDEX PER_NODE_PREFIX [NETWORK_INDEX]
#
# Called from mk-network-cr.sh as:
#   mk-nvipam-cidr.sh "${IPPOOL_NAME}" "${RANGE}" "${NETOP_GATEWAY_INDEX}" "${NETOP_PER_NODE_PREFIX}" "${NIDX}" >> ${FILE}
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"
IPPOOL_NAME="${1}"
NETWORK_RANGE="${2}"
GATEWAY_INDEX="${3}"
PER_NODE_PREFIX="${4}"
NETWORK_INDEX="${5:-}"
CIDRPOOL_ROUTES="${NETOP_CIDRPOOL_ROUTES:-}"

if [ -z "${CIDRPOOL_ROUTES}" ] && [ "${NETOP_SWITCH_PORT_MODE,,}" = "l3" ]; then
  CIDRPOOL_ROUTES="${NETWORK_RANGE}"
fi

function emit_cidrpool_exclusions()
{
  local -a exclusions=()
  local -a matching_ranges=()
  local entry
  local item
  local range_entry
  local idx
  local normalized
  local parsed
  local start_ip
  local end_ip

  if declare -p NETOP_NETWORK_EXCLUDE >/dev/null 2>&1; then
    case "$(declare -p NETOP_NETWORK_EXCLUDE)" in
    declare\ -a*)
      eval 'exclusions=( "${NETOP_NETWORK_EXCLUDE[@]}" )'
      ;;
    *)
      if [ -n "${NETOP_NETWORK_EXCLUDE:-}" ]; then
        exclusions=( "${NETOP_NETWORK_EXCLUDE}" )
      fi
      ;;
    esac
  fi

  if [ ${#exclusions[@]} -eq 0 ]; then
    return
  fi

  for item in "${exclusions[@]}"; do
    case "${item,,}" in
    ""|none|false|disabled)
      continue
      ;;
    esac
    normalized="${item//$'\n'/;}"
    normalized="${normalized//;/ }"
    for entry in ${normalized}; do
      idx=""
      range_entry="${entry}"
      if [[ "${entry}" == *,* ]]; then
        idx="${entry%%,*}"
        range_entry="${entry#*,}"
        if [ -n "${NETWORK_INDEX}" ] && [ "${idx}" != "${NETWORK_INDEX}" ]; then
          continue
        fi
      elif [ -n "${NETWORK_INDEX}" ]; then
        echo "ERROR: invalid NETOP_NETWORK_EXCLUDE entry '${entry}'. Use network-index,startIP-endIP entries." >&2
        exit 1
      fi
      matching_ranges+=( "${range_entry}" )
    done
  done

  if [ ${#matching_ranges[@]} -eq 0 ]; then
    return
  fi

  echo "  exclusions:"
  for range_entry in "${matching_ranges[@]}"; do
    parsed="${range_entry//,/ - }"
    parsed="${parsed//-/ - }"
    read -r start_ip _ end_ip _ <<< "${parsed}"
    if [ -z "${start_ip}" ] || [ -z "${end_ip}" ]; then
      echo "ERROR: invalid NETOP_NETWORK_EXCLUDE entry '${range_entry}'. Use network-index,startIP-endIP entries." >&2
      exit 1
    fi
    echo "  - startIP: ${start_ip}"
    echo "    endIP: ${end_ip}"
  done
}

cat <<POOLHEREDOC
---
apiVersion: nv-ipam.nvidia.com/v1alpha1
kind: CIDRPool
metadata:
  name: ${IPPOOL_NAME}
  namespace: ${NETOP_NAMESPACE}
spec:
  cidr: ${NETWORK_RANGE}
  gatewayIndex: ${GATEWAY_INDEX}
  perNodeNetworkPrefix: ${PER_NODE_PREFIX}
POOLHEREDOC

emit_cidrpool_exclusions

case "${CIDRPOOL_ROUTES,,}" in
none|false|disabled)
  CIDRPOOL_ROUTES=""
  ;;
esac

if [ -n "${CIDRPOOL_ROUTES}" ]; then
  echo "  routes:"
  CIDRPOOL_ROUTES="${CIDRPOOL_ROUTES//,/ }"
  for ROUTE_DST in ${CIDRPOOL_ROUTES}; do
    echo "  - dst: ${ROUTE_DST}"
  done
fi

cat <<POOLHEREDOC
  nodeSelector:
    nodeSelectorTerms:
    - matchExpressions:
      - key: ${NETOP_NODESELECTOR}
        operator: Exists
#       - key: node.su/${NETOP_SU}
#         operator: Exists
POOLHEREDOC
