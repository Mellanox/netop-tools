#!/bin/bash
#
# enable egress/ingress RDMA traffic
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-rdma-test
  namespace: default
spec:
  podSelector:
    matchLabels: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
EOF
