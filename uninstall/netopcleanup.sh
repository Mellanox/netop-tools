#!/bin/bash
#
#
helm uninstall -n network-operator network-operator --no-hooks
helm uninstall -n network-operator network-operator
helm repo list -n network-operator
k get job.batch
kn delete job.batch network-operator-sriov-network-operator-pre-delete-hook
kn delete ns -n network-operator
kn get all
# delete deployment
kn delete deployment network-operator-sriov-network-operator
kn delete deployment network-operator
#kn delete replicatset
# this seems to be cleaned up by the deployment
#

