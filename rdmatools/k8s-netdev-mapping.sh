#!/usr/bin/bash 
# Maps pcie/pf/vf/pod netdev & associated gpu

function gid_info()
{
  awk --assign net="${1}" '{ if ( $7 == net ) {print $1, $2, $3, $4, $5, $6, $7 }}' ${2} | grep v2 | grep -v fe80
}
function get_gpu_priority()
{
  idx=-1
  for CONNECTION in ${CONNECTION_LIST[@]}; do
    #echo ${CONNECTION}
    if [ "${CONNECTION} " = "${1}" ]; then
      echo "${idx}"
      return 
    fi
    let idx=idx+1
    if [ ${idx} -ge 8 ]; then
      echo ""
      return
    fi
  done
  echo ""
  return  # we didn't find any GPU
}

# Header
echo -e "NET_DEV\tRDMA_DEV\tVF_PCIe\tGPU_NIC_#\tBEST_CONNECTION\tCLOSEST_CUDA_DEV_#"
echo -e "-------\t--------\t-------\t---------\t---------------\t------------------"



# Loop over available netdevs 'net1', 'net2', etc
/root/show_gids > gid_info.$$
cat gid_info.$$ | grep v2 | grep -v fe80 | cut -f 7 | while read NET_DEV;do
  # print net dev
  #echo "For net dev:  ${NET_DEV}"

  # Get rdma netdev
  #RDMA_DEV=$(rdma link | grep netdev | grep ${NET_DEV} | cut -d ' ' -f2 | cut -d '/' -f1)
  #RDMA_DEV=$(/root/show_gids | grep -i ${NET_DEV} | grep v2 | grep -v fe80 | cut -f1)
  #echo ${NET_DEV} = ${RDMA_DEV}a
  GID_INFO=$(gid_info ${NET_DEV} gid_info.$$)
  RDMA_DEV=$(echo $GID_INFO |cut -d' ' -f1)
  GID_IDX=$(echo $GID_INFO |cut -d' ' -f3)
  
  # Check dmesg for the vf
  VF_PCI=$(dmesg | grep ${NET_DEV} | grep 'Link up' | tail -n 1 | cut -d']' -f2 | cut -d' ' -f3)
  #echo ${NET_DEV} = ${VF_PCI}
  if [ "${VF_PCI}" == "" ]; then
    VF_PCI="na"
  fi
  
  # Get nvidia-smi vf to Nic mapping
  nvidia-smi topo -m > smi_topo_info.$$
  GPU_NIC=$(cat smi_topo_info.$$ | grep ${RDMA_DEV} | cut -d ' ' -f3 | cut -d ':' -f1)
  #echo ${NET_DEV} nvidia-smi Nic = ${GPU_NIC}
  
  # Get the GPU
  # TODO: NV needs to be a substring, but it probably won't come up much
  CONNECTION_PRIORITY=( "NV" "PIX" "PXB" "PHB" "NODE" "SYS" )
  CONNECTION_LIST=$(cat smi_topo_info.$$ | grep "^${GPU_NIC}" | tr '\t' ' ' ) 
  #echo ${CONNECTION_LIST}
  for PRIORITY in ${CONNECTION_PRIORITY[@]}; do
      GPU=$(get_gpu_priority "${PRIORITY} ") 
      #echo ${GPU}
      if [ "${GPU}" != "" ]; then
        #echo ${NET_DEV} best GPU link = ${PRIORITY}
	#echo ${NET_DEV} best GPU = CUDA device ${GPU}
	echo -e "${NET_DEV},${RDMA_DEV},${VF_PCI},${GPU_NIC},${PRIORITY},${GPU}"
        break
      fi
  done
  if [ "${GPU}" = "" ];then
     echo -e "${NET_DEV},${RDMA_DEV},${VF_PCI},${GPU_NIC},${PRIORITY},NA"
  fi
done
