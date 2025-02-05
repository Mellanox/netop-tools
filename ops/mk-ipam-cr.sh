#!/bin/bash
#
# make the ipam config based on IPAM_TYPE
#
function whereabouts()
{
NIDX=${1}
shift
cat <<HEREDOC1
  ipam: |
    {
      "type": "${IPAM_TYPE}",
      "datastore": "kubernetes",
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/${IPAM_TYPE}.d/${IPAM_TYPE}.kubeconfig"
      },
      "range": "${NETOP_NETWORK_RANGE}",
      "exclude": [],
      "log_file": "/var/log/${IPAM_TYPE}.log",
      "log_level": "info"
    }
HEREDOC1
}
function nv_ipam_config()
{
NIDX=${1}
shift
cat <<HEREDOC2
  ipam: |
    {
      "type": "${IPAM_TYPE}",
      "datastore": "kubernetes",
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/${IPAM_TYPE}.d/${IPAM_TYPE}.kubeconfig"
      },
      "log_file": "/var/log/${NETOP_NETWORK_TYPE}_${IPAM_TYPE}.log",
      "log_level": "debug",
      "poolName": "${NETOP_NETWORK_POOL}-${NIDX}",
      "poolType": "${NVIPAM_POOL_TYPE}"
    }
HEREDOC2
}
function dhcp_config()
{
NIDX=${1}
shift
cat <<HEREDOC3
  ipam: |
    {
      "type": "${IPAM_TYPE}",
      "daemonSocketPath": "/run/cni/dhcp.sock",
      "request": [
        {
          "skipDefault": false,
          "option": "classless-static-routes"
        }
      ],
      "provide": [
        {
          "option": "host-name",
          "fromArg": "K8S_POD_NAME"
        }
      ]
    }
HEREDOC3
}
function mk_ipam_cr()
{
  case ${IPAM_TYPE} in
  whereabouts)
    whereabouts ${1}
    ;;
  nv-ipam)
    nv_ipam_config ${1}
    ;;
  dhcp)
    dhcp_config ${1}
    ;;
  esac
}
