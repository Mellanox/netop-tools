#!/bin/bash
#
# Generate DRA (Dynamic Resource Allocation) CRs for the SR-IOV DRA driver
# (26.4.0+). Emits a DeviceClass + ResourceClaimTemplate per device in
# NETOP_NETLIST so pods can claim VFs via resourceClaims instead of via the
# legacy SR-IOV device plugin.
#
# Required env (from global_ops.cfg / usecase/netop.cfg):
#   NETOP_NETLIST, NETOP_SULIST, NETOP_NETWORK_NAME, NETOP_NAMESPACE,
#   NETOP_RESOURCE, NETOP_TAG_VERSION, NETOP_VERSION
#
# TODO_DRIVER_NAME placeholder must be replaced with the actual driver name
# that the dra-driver-sriov DaemonSet publishes in ResourceSlice.spec.driver
# (e.g. "sriov.network-operator.nvidia.com" — confirm against running cluster
# or v26.4.0 docs once published).
#
source ${NETOP_ROOT_DIR}/global_ops.cfg

case ${NETOP_VERSION} in
  26.4.*)
    ;;
  *)
    echo "ERROR: mk-dra-cr.sh requires NETOP_VERSION 26.4.x or later (current: ${NETOP_VERSION})"
    exit 1
    ;;
esac

DRA_API_VERSION="${DRA_API_VERSION:-resource.k8s.io/v1beta1}"
DRA_DRIVER_NAME="${DRA_DRIVER_NAME:-TODO_DRIVER_NAME}"

function init_file()
{
  if [ "${NETOP_TAG_VERSION}" == true ];then
    echo "# VERSION:${NETOP_VERSION}" > "${1}"
  else
    rm -f "${1}"
  fi
}

NETOP_DRA_FILES=()
DRA_IDX=0

for NETOP_SU in ${NETOP_SULIST[@]};do
  for NIDXDEF in ${NETOP_NETLIST[@]};do
    NIDX=$(echo ${NIDXDEF}|cut -d',' -f1)

    DEVICE_CLASS="${NETOP_NETWORK_NAME}-${NIDX}-${NETOP_SU}-class"
    CLAIM_TEMPLATE="${NETOP_NETWORK_NAME}-${NIDX}-${NETOP_SU}-claim"
    FILE="dra-${NIDX}-${NETOP_SU}.yaml"
    NETOP_DRA_FILES[${DRA_IDX}]="${FILE}"
    let DRA_IDX=DRA_IDX+1
    init_file "${FILE}"

cat <<DRA_CRS >> ${FILE}
---
apiVersion: ${DRA_API_VERSION}
kind: DeviceClass
metadata:
  name: ${DEVICE_CLASS}
spec:
  selectors:
    - cel:
        expression: device.driver == "${DRA_DRIVER_NAME}"
---
apiVersion: ${DRA_API_VERSION}
kind: ResourceClaimTemplate
metadata:
  name: ${CLAIM_TEMPLATE}
  namespace: ${NETOP_NAMESPACE}
spec:
  spec:
    devices:
      requests:
        - name: ${NETOP_RESOURCE}-${NIDX}
          exactly:
            deviceClassName: ${DEVICE_CLASS}
            count: 1
DRA_CRS
  done
done

if [ ${#NETOP_DRA_FILES[@]} -gt 0 ];then
  echo ${NETOP_DRA_FILES[@]} > netop_dra_files
fi
