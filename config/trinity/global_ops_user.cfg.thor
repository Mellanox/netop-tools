# Vendor: NVIDIA
#
#System Information
#       Manufacturer: NVIDIA
#       Product Name: NVIDIA IGX Orin Development Kit
#       Version: Not Specified
#       Serial Number: 1411523000174
#
# needed in worker node grub default config: iommu=pt intel_iommu=on
#
NETOP_VERSION="26.4.0"
PROD_VER=1
#NGC_API_KEY=$(cat /home/thuff/keys/ngc/ngc_staging_personal_key)
NIC_CONFIG_ENABLE=false
#K8SVER="1.32"
NFD_ENABLE=true
OFED_ENABLE=false
CREATE_CONFIG_ONLY=0
USECASE="sriovnet_rdma"
DEVICE_TYPES=( "connectx-7" )
NUM_VFS=8
#NUM_GPUS=1
NUM_GPUS=0
NETOP_NAMESPACE="network-operator"
NETOP_BCM_CONFIG=true
NETOP_COMBINED=true
NETOP_SRIOV_NODE_POOL="100%"
NETOP_NICCLUSTER_FILE="nic-cluster-policy-rtx6000ada.yaml"
NETOP_NODEPOOLS=( "NETOP_NETLIST_IGX" "NETOP_NETLIST_OVX" )
NETOP_NETLIST_IGX=( a,,,0004:03:00.0 b,,,0004:03:00.1 )
NETOP_NODESELECTOR_IGX="kubernetes.io/arch"
NETOP_NODESELECTOR_VAL_IGX="arm64"
NETOP_NETLIST_OVX=( a,,,0000:16:00.0 b,,,0000:16:00.1 c,,,0000:b8:00.0 d,,,0000:b8:00.1 )
NETOP_NODESELECTOR_OVX="kubernetes.io/arch"
NETOP_NODESELECTOR_VAL_OVX="amd64"
# IGX and OVX are on the same L2 fabric — shared IPPool, single CIDR
NETOP_NETWORK_RANGE="192.168.0.0/16"
OFED_BLACKLIST_ENABLE=true
#OFED_BLACKLIST_ADD="irdma:ice:i40e:i40iw"
ENTRYPOINT_DEBUG=true
#OFED_BLACKLIST_MODULES="irdma,ice"
