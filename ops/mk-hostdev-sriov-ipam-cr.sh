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
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/ops/mk-ipam-cr.sh
if [ "$#" -ne 4 ];then
  echo "usage:$0 {NETWORK_NAME} {IPPOOL_NAME} {NETWORK IDX} {NETOP_APP_NAMESPACE}"
  echo "example:$0 networkname ippoolname a default"
  exit 1
fi
NETWORK_NAME="${1}"
shift
IPPOOL_NAME="${1}"
shift
NIDX=${1}
shift
NETOP_APP_NAMESPACE=${1}
shift
cat <<HEREDOC
---
apiVersion: mellanox.com/v1alpha1
kind: ${NETOP_NETWORK_TYPE}
metadata:
  name: ${NETWORK_NAME}
  namespace: ${NETOP_NAMESPACE}
spec:
  networkNamespace: "${NETOP_APP_NAMESPACE}"
  resourceName: "${NETOP_RESOURCE}_${NIDX}"
HEREDOC
mk_ipam_cr ${IPPOOL_NAME}
