#!/bin/bash
#
# Configure Calico BIRD firewall rules securely
# Opens port 179 for BGP communication between nodes
#
# Usage: fix_calico_bird.sh [CLUSTER_SUBNET]
#   CLUSTER_SUBNET: Network CIDR for cluster nodes (e.g., 10.185.179.0/24)
#   If not provided, uses restricted localhost-only rule
#

# Source global configuration to get cluster network information
if [ -f "${NETOP_ROOT_DIR}/global_ops.cfg" ]; then
    source "${NETOP_ROOT_DIR}/global_ops.cfg"
fi

CLUSTER_SUBNET="${1:-}"

# Use parameter if provided, otherwise try to detect from config
if [ -z "$CLUSTER_SUBNET" ]; then
    # Try to get from global config or use secure default
    if [ -n "$K8CIDR" ]; then
        CLUSTER_SUBNET="$K8CIDR"
        echo "Using cluster CIDR from config: $CLUSTER_SUBNET"
    else
        # Secure default - only localhost (requires manual configuration)
        CLUSTER_SUBNET="127.0.0.1/32"
        echo "WARNING: No cluster subnet specified. Using localhost-only access."
        echo "To allow cluster communication, run: $0 <CLUSTER_SUBNET>"
        echo "Example: $0 10.185.179.0/24"
    fi
fi

echo "Configuring BIRD BGP port 179 for subnet: $CLUSTER_SUBNET"
iptables -A INPUT -s "$CLUSTER_SUBNET" -p tcp -m tcp --dport 179 -j ACCEPT

# SECURITY NOTE: Never use 0.0.0.0 as source - it allows all internet traffic!
# Original insecure rule: iptables -A INPUT -s 0.0.0.0 -p tcp -m tcp --dport 179 -j ACCEPT


