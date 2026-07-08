#!/bin/bash
#
# Generate DRA (Dynamic Resource Allocation) CRs for the SR-IOV DRA driver
# (26.4.0+). Emits one ResourceClaimTemplate per device in NETOP_NETLIST.
#
# Modeled on the per-step examples in NVIDIA's "DRA SR-IOV Driver" doc:
#   https://mellanox.github.io/network-operator-docs/dra-sriov-driver/dra-sriov-driver.html
#
# The DeviceClass `sriovnetwork.k8snetworkplumbingwg.io` is auto-created by
# the dra-driver-sriov DaemonSet — netop-tools does not generate it. We just
# reference it from each ResourceClaimTemplate and narrow to a per-device
# resource pool via a CEL selector on resourceName.
#
# Required env (from global_ops.cfg / usecase/netop.cfg):
#   NETOP_NETLIST, NETOP_SULIST, NETOP_NETWORK_NAME, NETOP_NAMESPACE,
#   NETOP_RESOURCE_PATH, NETOP_RESOURCE, NETOP_TAG_VERSION, NETOP_VERSION
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

DRA_API_VERSION="${DRA_API_VERSION:-resource.k8s.io/v1}"
# Driver name from k8snetworkplumbingwg/dra-driver-sriov/pkg/consts/consts.go.
# Used directly as deviceClassName (the DaemonSet creates the matching cluster-
# wide DeviceClass automatically).
DRA_DEVICE_CLASS="${DRA_DEVICE_CLASS:-sriovnetwork.k8snetworkplumbingwg.io}"

function init_file()
{
  if [ "${NETOP_TAG_VERSION}" == true ];then
    echo "# VERSION:${NETOP_VERSION}" > "${1}"
  else
    rm -f "${1}"
  fi
}
function set_su_values()
{
  NETOP_SU_VALUES=( "${NETOP_SULIST[@]}" )
  if [ ${#NETOP_SU_VALUES[@]} -eq 0 ];then
    NETOP_SU_VALUES=( "" )
  fi
}

NETOP_DRA_FILES=()
DRA_IDX=0

set_su_values
for NETOP_SU in "${NETOP_SU_VALUES[@]}";do
  SUTAG="${NETOP_SU:+-${NETOP_SU}}"
  for NIDXDEF in ${NETOP_NETLIST[@]};do
    NIDX=$(echo ${NIDXDEF}|cut -d',' -f1)

    CLAIM_TEMPLATE="${NETOP_NETWORK_NAME}-${NIDX}${SUTAG}-claim"
    RESOURCE_NAME="${NETOP_RESOURCE_PATH}/${NETOP_RESOURCE}_${NIDX}"
    FILE="dra-${NIDX}${SUTAG}.yaml"
    NETOP_DRA_FILES[${DRA_IDX}]="${FILE}"
    let DRA_IDX=DRA_IDX+1
    init_file "${FILE}"

cat <<DRA_CRS >> ${FILE}
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
        - name: vf
          exactly:
            deviceClassName: ${DRA_DEVICE_CLASS}
            count: 1
            selectors:
              - cel:
                  expression: >
                    device.attributes["k8s.cni.cncf.io"].resourceName == "${RESOURCE_NAME}"
DRA_CRS
  done
done

if [ ${#NETOP_DRA_FILES[@]} -gt 0 ];then
  echo ${NETOP_DRA_FILES[@]} > netop_dra_files
fi
