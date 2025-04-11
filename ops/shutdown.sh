#!/bin/bash
#
# https://yourdevopsmentor.com/blog/how-to-stop-all-kubernetes-deployments/
# https://www.bmc.com/blogs/kubernetes-daemonset/
#
NAMESPACES=( "default" "${NETOP_NAMESPACE}" "calico-system"  "kube-system" )
#
# delete all depolyments
#
for NAMESPACE in ${NAMESPACES[@]};do
  kubectl --namespace ${NETOP_NAMESPACE} scale deployment $(kubectl --namespace ${NVNOP_NAMESPACE} get deployment | awk '{print $1}') --replicas 0
done
#
# delete all daemon sets
#
for NAMESPACE in ${NAMESPACES[@]};do
  kubectl --namespace ${NETOP_NAMESPACE} delete daemonset $(kubectl --namespace ${NVNOP_NAMESPACE} get daemonset | awk '{print $1}') --replicas 0
done
#
# delete all stateful sets
#
for NAMESPACE in ${NAMESPACES[@]};do
  kubectl --namespace ${NETOP_NAMESPACE} scale statefulset --replicas 0 $(kubectl --namespace ${NVNOP_NAMESPACE} get statefulset  | awk '{print $1}')
done
#
# delete all resources
#
for NAMESPACE in ${NAMESPACES[@]};do
  kubectl delete all --all --namespace ${NETOP_NAMESPACE}
done
