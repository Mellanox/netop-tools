#!/bin/bash -x
#
# configure the secondary network
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/mk-ipam-cr.sh
if [ "$#" -ne 3 ];then
  echo "usage:$0 {NETWORK INDEX} {NETOP_SU} {NETOP_APP_NAMESPACE}"
  echo "example:$0 a su-1 default"
  exit 1
fi
NIDX=${1}
NETOP_SU=${2}
NETOP_APP_NAMESPACE=${3}

FILE="${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}-cr.yaml"
cat <<HEREDOC1> ${FILE}
apiVersion: sriovnetwork.openshift.io/v1
kind: ${NETOP_NETWORK_TYPE}
metadata:
  name: "${FILE%%-cr.yaml}"
  namespace: ${NETOP_NAMESPACE}
spec:
HEREDOC1
if [ "${NETOP_NETWORK_TYPE}" = "SriovNetwork" ];then
  echo "  vlan: ${NETOP_NETWORK_VLAN}" >> ${FILE}
else
  echo "  linkState: enable" >> ${FILE}
fi
cat <<HEREDOC2>> ${FILE}
  networkNamespace: "${NETOP_APP_NAMESPACE}"
  resourceName: "${NETOP_RESOURCE}_${NIDX}"
HEREDOC2
mk_ipam_cr ${NIDX} ${NETOP_SU} >> ${FILE}
echo ${FILE}
