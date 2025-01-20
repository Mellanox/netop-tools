#!/bin/bash
# Copyright 2024 NVIDIA
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# https://github.com/Mellanox/network-operator/tree/master/example/crs
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/mk-ipam-cr.sh
if [ "$#" -ne 4 ];then
  echo "usage:$0 {NETWORK_MASTER DEV} {NETWORK IDX} {SCALABLE_UNIT} {NETOP_APP_NAMESPACE}"
  echo "example:$0 ens1f0np0 a default"
  exit 1
fi
NDEV=${1}
shift
NIDX=${1}
shift
NETOP_SU=${1}
shift
NETOP_APP_NAMESPACE=${1}
shift
FILE="${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}-cr.yaml"
cat <<HEREDOC> "${FILE}"
apiVersion: mellanox.com/v1alpha1
kind: ${NETOP_NETWORK_TYPE}
metadata:
  name: ${NETOP_NETWORK_NAME}-${NETOP_APP_NAMESPACE}-${NIDX}-${NETOP_SU}
  namespace: ${NETOP_NAMESPACE}
spec:
  networkNamespace: "${NETOP_APP_NAMESPACE}"
  master: "${NDEV}"
  mode: "bridge"
  mtu: 1500
HEREDOC
mk_ipam_cr ${NIDX}-${NETOP_SU} >> "${FILE}"
echo ${FILE}
# "gateway": "${NETOP_NETWORK_GW}" # for ipam config above may need to set depending on fabric design
