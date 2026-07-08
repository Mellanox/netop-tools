#!/bin/bash
#
# can take up to 10 minutes to synch
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL} get sriovnetworknodestates.sriovnetwork.openshift.io -A
