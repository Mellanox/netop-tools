#!/bin/bash
#
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
${K8CL}  get sriovnetworknodepolicies.sriovnetwork.openshift.io -A
