#!/bin/bash
#
#
#
git clone https://github.com/Mellanox/nic-configuration-operator.git /tmp/nic-configuration-operator
cd /tmp/nic-configuration-operator

# Use the tag matching your Network Operator release if present
git checkout network-operator-v${NETOP_VERSION}

kubectl apply -f deployment/nic-configuration-operator-chart/crds
kubectl wait --for=condition=Established crd/nicconfigurationtemplates.configuration.net.nvidia.com --timeout=60s
