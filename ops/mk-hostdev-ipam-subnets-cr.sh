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
if [ "$#" -lt 2 ];then
  echo "usage:$0 {NETWORK_NAME} {NETWORK_DEV_LIST}"
  echo "example:$0 hostnet-rdma-shared-device a b c d e f g h"
  exit 1
fi
source ${NETOP_ROOT_DIR}/global_ops.cfg
NETWORK_NAME=${1}
shift
RESOURCE=`echo ${NETWORK_NAME}|cut -d'-' -f2-99|sed 's/-/_/g'`
for NETOP_APP_NAMESPACE in ${NETOP_APP_NAMESPACES[@]};do
FILE="${NETOP_NETWORK_NAME}-${NIDX}-${NETOP_APP_NAMESPACE}-cr.yaml"
IDX=0
for DEV in ${*};do
cat <<HEREDOC> "${NETWORK_NAME}-${DEV}"-cr.yaml
apiVersion: mellanox.com/v1alpha1
kind: "${NETOP_NETWORK_TYPE}"
metadata:
  name: "${NETWORK_NAME}-${DEV}"
spec:
  networkNamespace: "${NETOP_APP_NAMESPACE}"
  resourceName: "${RESOURCE}_${DEV}"
  ipam: |
    {
      "type": "${IPAM_TYPE}",
      "datastore": "kubernetes",
      "kubernetes": {
        "kubeconfig": "/etc/cni/net.d/whereabouts.d/whereabouts.kubeconfig"
      },
      "range": "192.169.${IDX}.0/24",
      "exclude": [],
      "log_file": "/var/log/whereabouts.log",
      "log_level": "info"
    }
HEREDOC
let IDX=IDX+1
done
done
