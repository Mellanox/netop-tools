#!/bin/bash
#
# delete the host networks, the ip  pool
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
  for NIDXDEF in ${NETOP_NETLIST[@]};do
    NIDX=`echo ${NIDXDEF}|cut -d',' -f1`
    FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-cr.yaml"
    if [ -f ${FILE} ];then
      kubectl delete -f ${FILE}
    else
      echo "WARNING:not found:${FILE}"
    fi
  done
done
#
# delete ippool 
#
kubectl get ${NETOP_NETWORK_TYPE}
if [ "${IPAM_TYPE}" = "nv-ipam" ];then
  FILE="${NETOP_ROOT_DIR}/usecase/${USECASE}/ippool.yaml"
  if [ -f ${FILE} ];then
    kubectl delete -f ${FILE}
  else
    echo "WARNING:not found:${FILE}"
  fi
fi
