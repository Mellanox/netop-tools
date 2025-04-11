#!/bin/bash
#
#
#
Jeff,

A new image is needed, but not a new helm chart.
Some existing config yaml files will need to be modified.

# I copied my 23.05 network operator helm config to a new dir
# on the master node go to the top level that includes the netop-chart/network-operator helm charts.
# in my case.
cd ./netop

# copy the exiting helm chart configuration to a chart dir for sriov-dp-volume
cp -Rp ~/netop/netop-chart-23.5.0 ~/netop/netop-chart-23.5.0-sriov-dp-volume

# backup your overrides values.yaml file
cp network-operator-values-23.5.0.yaml network-operator-values-23.5.0.yaml.back

# create a copy of your values.yaml for the  netop-chart-23.5.0-sriov-dp-volume configuration
cp network-operator-values-23.5.0.yaml network-operator-values-23.5.0-sriov-dp-volume.yaml

# I symlink value.yaml to my release specific config
# if the symlink values.yaml already exists you must remove it. rm -f values.yaml
ln -s ./release/network-operator-values-23.5.0-sriov-dp-volume.yaml values.yaml

# I do the same with the netop-chart directory
rm -f netop-chart
ln -s ./release/netop-chart-23.5.0-sriov-dp-volume netop-chart

# The config needs to be modified to select the staging image and the appVersion in the
# set the appVersion, file needs to be modified to match the new application name
~/netop/netop-chart/network-operator/Chart.yaml

< appVersion: v23.5.0
--
> appVersion: v23.5.0-sriov-dp-volume

# set the image repository
~/netop/netop-chart/network-operator/values.yaml

< repository: nvcr.io/nvidia/cloud-native
--
> repository: nvcr.io/nvstaging/mellanox


# because this is not in the cloud-native repository you’ll need to replicate the process you use for logging into pull the image.
# I preloaded the images into my nodes using crictl.
export NETOP_VERSION="23.5.0-sriov-dp-volume"
export NGC_API_KEY=`cat /root/.ngc/config|grep apikey|cut -d' ' -f3`
crictl pull --creds '$oauthtoken':${NGC_API_KEY} nvcr.io/nvstaging/mellanox/network-operator:v${NETOP_VERSION}

# then I ran the upgrade script, I’m attaching the scripts I use as example scripts.
# if YOU use the scripts below, YOU will need to edit to match you environment.
# I’m using namespace nvidia-network-operator
# I’m using calico for my secondary network plugin.

# ${NETOP_ROOT_DIR}/global_ops.cfg                    # set my env variable
# cordon.sh             # cordon the worker nodes
# netchartlinks.sh  # set the symbolic links which you did manual above
# applycrds.sh        # apply the cluster resource definitions

#!/bin/bash -x
#
#
source ${NETOP_ROOT_DIR}/global_ops.cfg
source ./cordon.sh
source ./netchartlnks.sh
cordon
cd netop-chart
${K8CL} scale deployment --replicas=0 -n ${NETOP_NAMESPACE} network-operator
../applycrds.sh
helm upgrade -n ${NETOP_NAMESPACE}  network-operator network-operator  -f ../network-operator-values-${NETOP_VERSION}.yaml
uncordon


#
#
#

Call me to talk though this.

Tom

