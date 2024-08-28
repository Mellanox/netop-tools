# netop-tools
tools to install and configure nvididsa network operator based on use cases
download repo

1. ls ./usecase
Select the usecase configuration example that matches your expected cluster configuration.

hostnet_rdma_shared_device_ipam uses: HostDeviceNetwork network type to define the network operator networks with the rdmaSharedDevicePlugin. Used whereabouts ipam plugin for IP 2ndary network allocaltion, limited to 50 nodes.
hostnet_rdma_shared_device_nvipam:    HostDeviceNetwork network type to define the network operator networks with the rdmaSharedDevicePlugin. Used nv-ipam plugin for IP 2ndary network allocaltion, scales past 50 nodes.
hostnet_rdma_sriov_ipam:              HostDeviceNetwork network type to define the network operator networks with the sriovDevicePlugin. Used whereabouts ipam plugin for IP 2ndary network allocaltion, limited to 50 nodes.
hostnet_rdma_sriov_nvipam             HostDeviceNetwork network type to define the network operator networks with the sriovDevicePlugin. Used nv-ipam plugin for IP 2ndary network allocaltion, scales past 50 nodes.
sriovnet_rdma_ipam                    SriovNetwork network type to define the network operator networks with the sriovNetworkOperator plugin. Used whereabouts ipam plugin for IP 2ndary network allocaltion, limited to 50 nodes.
sriovnet_rdma_nvipam                  SriovNetwork network type to define the network operator networks with the sriovNetworkOperator. Used nv-ipam plugin for IP 2ndary network allocaltion, scales past 50 nodes.
sriovibnet_rdma_ipam                  SriovIbNetwork network type to define the network operator networks with the sriovNetworkOperator plugin. Used whereabouts ipam plugin for IP 2ndary network allocaltion, limited to 50 nodes.
sriovibnet_rdma_nvipam                SriovIbNetwork network type to define the network operator networks with the sriovNetworkOperator. Used nv-ipam plugin for IP 2ndary network allocaltion, scales past 50 nodes.

from netop-tools run:
./setsymlinks.sh {usecase}

Then edit the selected usecase configuration.
cd ./uc
edit the netop.cfg file to set your configuration values.
Example for sriovnet_rdma_nvipam.
export K8CIDR="192.168.0.0/16"                      # this is your k8s cluster CIDR
export K8SVER="1.29"                                # select the required K8S version
export HOSTOS="ubuntu"                              # select the host OS, could be pulled frrom the config
export NETOP_NAMESPACE="nvidia-network-operator"    # set the nvidia network operator name space. may differ in your cluster
export NETOP_APP_NAMESPACE="default"                # set the name space that your application pods will run in. may vary in your cluster
export NETOP_NETWORK_TYPE="SriovNetwork"            # define the type of network HostDevNetwork or SriovNetwork
export NETOP_NETWORK_NAME="net-rdma-sriov"          # define a name for your nbetwoprk-work-operator secondary networks
export NETOP_NETWORK_POOL="sriovnet-pool"           # define a name for you nvipam ip pools
export NETOP_NETWORK_RANGE="192.169.0.0/16"         # define the IP pool for your secondary rdma network. different from the K8S CDIR
export NETOP_NETWORK_GW="192.169.0.1"               # define the gateway IP for your secondary rdma network for your cluster
export NETOP_PERNODE_BLOCKSIZE="32"                 # define the number of IP addrs that can be allocated per worker node inyour cluster from the nvipam pool
export NETOP_NETWORK_VLAN="0"                       # define the VLAN
export NETOP_RESOURCE="sriov_resource"              # define the name of the network resource
export PROD_VER=1 # is this a production version    # selection product vs dev releases
if [ "${PROD_VER}" = "1" ];then
  export NETOP_VERSION="24.1.1"                     # select netrwork operator version
# export NETOP_HELM_URL="https://helm.ngc.nvidia.com/nvidia/cloud-native/charts/network-operator-${NETOP_VERSION}.tgz"
  export HELM_NVIDIA_REPO="https://helm.ngc.nvidia.com/nvidia"     # helm repo URL
  export NETOP_HELM_URL="https://helm.ngc.nvidia.com/nvidia/charts/network-operator-${NETOP_VERSION}.tgz"  # helm chart tarball
else
  export NETOP_VERSION="24.7.0-rc.2"               # select netrwork operator version
  export HELM_NVIDIA_REPO="https://helm.ngc.nvidia.com/nvstaging"  # helm repo URL
  export NETOP_HELM_URL="https://helm.ngc.nvidia.com/nvstaging/mellanox/charts/network-operator-${NETOP_VERSION}.tgz" # helm chart tarball
  export NGC_API_KEY=`cat /root/.ngc/config|grep apikey|cut -d' ' -f3` # dev NGC_API_KEY
  export NGC_SECRET="ngc-image-secret"                                 # dev image secret
fi
export IPAM_TYPE="nv-ipam"                         # select type of ipam, whereabouts (ipam), nv-ipam plugin (nv-ipam)
export CALICO_ROOT="3.27.2"                        # select calico secondary network CNI (cluster network inetrface)
export CALICO_VERSION="v${CALICO_ROOT}"            # calico, flanne, cilium

edit the values.yaml

leave the use case directory
cd ..

install k8s, calico, and network-operator on a clean system.
from the netop-tools directory run:
./insk8.sh

#!/bin/bash -x
#
# install k8 master for first time
#
source ./netop.cfg
cd ./install
./ins-k8master.sh master
./ins-k8master.sh init
./ins-k8master.sh calico
./ins-k8master.sh netop
kubectl get nodes

After the install you'll need to add worker nodes.
The simplest way is make you control-plane master node a works.

cd ../ops
./labelworker.sh {nodename}

The networkop operator will discover the worker node resources using the
nvidia-network-operator   sriov-network-config-daemon pod to discover the configuration
and configure the VFs on the worknodes. 

Then the nvidia-network-operator   sriov-device-plugin pod builds the network resource pools from the discovered devices.

After the network resource pools are defined mofed node will start installing.
nvidia-network-operator   mofed-ubuntu22.04-9d75cb66f-ds-vhpwp 

This will get network-operator in the running state, depending on your system each step can take several minutes.
If you have a non-standard kernel, networkwork operator will compile the MOFED kernel modules and this can take a long time.
On some systems it takes over 70 minutes.
The modules are cached, and will get reused on subsequent runs.

When network operator is in the ready state then you must create you network resources.

cd ./uc
review your networkcfg.sh script and edit to match your configuration

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
verify that the NicClusterPolicy is in the ready state.
kubectl get NicClusterPolicy 
The status should be ready.

Then install an application
now we can run a sample application
This example will get installed in the defsault namespace.
./installapp.sh test1 a {optional node assignment}

This sample will start a pod with a single secondary network device from network a
This can be edited to have parallel networks and resource requests.

Verify that you test1 pod is running
kubectl get pods

examine the test1 pod
kubectl exec -it test1 -- bash

inspect the network configuration in the pod.
you should see the default eth0 device assigned by the K8s primary network.
Also you should net a net1 device for your secondary netwoprk device.
The should have separate IP addresses from the separate CIDR ranges.

Setup a second pod on the same network, it should get separate devices.
./installapp.sh test2 a

Then you should be able to pass traffic between them using ib_write_bw.
