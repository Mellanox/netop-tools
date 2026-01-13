#!/bin/bash
#
# must be configured to use crictl to read container runtime info
# run on each node that you want to inspect containers on at the node level.
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ${NETOP_ROOT_DIR}/install/detect_runtime.sh

detect_container_runtime

cat << HEREDOC > /etc/crictl.yaml
runtime-endpoint: ${CRI_SOCKET}
image-endpoint: ${CRI_SOCKET}
timeout: 30
debug: true
pull-image-on-create: false
disable-pull-on-run: false
HEREDOC

echo "Configured crictl for ${CONTAINER_RUNTIME} runtime"
