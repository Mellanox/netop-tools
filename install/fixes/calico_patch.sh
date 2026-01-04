#!/bin/bash
# Check current installation
kubectl get installation default -o yaml | grep -A10 calicoNetwork

# Patch to use VXLAN and correct IP detection
kubectl patch installation default --type=merge -p '
spec:
  calicoNetwork:
    bgp: Disabled
    ipPools:
    - cidr: 192.168.0.0/16
      encapsulation: VXLAN
      natOutgoing: Enabled
      nodeSelector: all()
    nodeAddressAutodetectionV4:
      cidrs:
        - 10.185.179.0/24
'
#        - 192.168.200.0/24 ???? should above CIDR be replaced with this?????
#
###kubectl patch installation default --type=merge -p '{"spec":{"calicoNetwork":{"bgp":"Disabled"}}}'
###
#### Wait for operator to apply
###sleep 10
###
#### Restart calico-node to pick up changes
###kubectl rollout restart daemonset/calico-node -n calico-system
###
#### Watch pods
###kubectl get pods -n calico-system -l k8s-app=calico-node -w
#
# fixing calico auto-detection error
#
kubectl patch installation default --type=json -p='[
  {"op": "remove", "path": "/spec/calicoNetwork/nodeAddressAutodetectionV4/firstFound"},
  {"op": "replace", "path": "/spec/calicoNetwork/nodeAddressAutodetectionV4/cidrs", "value": ["192.168.200.0/24"]}
]'
#  {"op": "replace", "path": "/spec/calicoNetwork/nodeAddressAutodetectionV4/cidrs", "value": ["10.185.179.0/24"]}
