#!/bin/bash
source ${NETOP_ROOT_DIR}/global_ops.cfg
CRDS=$(kubectl -n ${NETOP_NAMESPACE}  --no-headers get crds|cut -d' ' -f1)
for CRD in ${CRDS[@]};do
  echo "${CRD}"
  RESOURCES=$(kubectl -n ${NETOP_NAMESPACE} --no-headers get crd ${CRD}|cut -d' ' -f1)
  for RESOURCE in ${RESOURCES[@]};do
    FINALIZERS=$(kubectl -n ${NETOP_NAMESPACE} get crd ${CRD} ${RESOURCE} -o yaml | grep -i finalizer )
    for FINALIZER in ${FINALIZERS[@]};do
      echo "${CRD}:${RESOURCE}:${FINALIZER}"
    done
  done
done
