#!/bin/bash -x
#
# setup the host networks, and make the nvipam ip pool
# typically in a GPU/NIC system you'll deploy multiple parallel 2ndary networks.
#
# in this example we are defining 2 networks a and b
# these are arbritary strings
# for example:
# a_0 a_1 b_0 b_1 would define 4 networks using 2 dual port nics
# a b c d e f g would define 8 network for 8 nics.
source ./netop.cfg
#
# set the SriovNetwork configuration files
# sriov policy file
# sriov node policy file
# NetworkAttachmentDefinition file
#
# network a on NIC 0000:23:00.0
./ops/mk-sriovpolicy.sh 0000:23:00.0 a
kubectl apply -f sriovnetwork-node-policy-a.yaml
./ops/mk-network-attachment.sh a
kubectl apply -f "./Network-Attachment-Definitions-a.yaml"
# network b on 0000:24:00.0
./ops/mk-sriovpolicy.sh 0000:24:00.0 b
kubectl apply -f sriovnetwork-node-policy-b.yaml
./ops/mk-network-attachment.sh b
kubectl apply -f "./Network-Attachment-Definitions-b.yaml"
#
# define the custom resource by network using the same network labels
#
# loop through and apply the network CRD's
./ops/mk-sriovnet-nvipam-cr.sh ${NETOP_NETWORK_NAME} a b
NETWORKS=$(ls ${NETOP_NETWORK_NAME}*.yaml)
for NETWORK in ${NETWORKS[@]};do
  kubectl apply -f ./${NETWORK}
done
#
# create the nv-ipam ip pool
#
./ops/mk-nvipam.sh
kubectl apply -f ippool.yaml
#
# verify the network devices
#
./ops/getnetwork.sh
