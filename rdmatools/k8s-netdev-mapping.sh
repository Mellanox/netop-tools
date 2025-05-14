#!/usr/bin/bash 
# Maps pcie/pf/vf/pod netdev & associated gpu

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


# Loop over available netdevs 'net1', 'net2', etc
rdma link | grep netdev | cut -d ' ' -f8 | while read NET_DEV;do
  # print net dev
  echo "For net dev:  ${NET_DEV}"

  # Get rdma netdev
  RDMA_DEV=$(rdma link | grep netdev | grep ${NET_DEV} | cut -d ' ' -f2 | cut -d '/' -f1)
  echo ${NET_DEV} = ${RDMA_DEV}
  
  # Check dmesg for the vf
  VF_PCI=$(dmesg | grep ${NET_DEV} | grep 'Link up' | tail -n 1 | cut -d ' ' -f3)
  echo ${NET_DEV} = ${VF_PCI}
  
  # Get nvidia-smi vf to Nic mapping
  GPU_NIC=$(nvidia-smi topo -m | grep ${RDMA_DEV} | cut -d ' ' -f3 | cut -d ':' -f1)
  echo ${NET_DEV} nvidia-smi Nic = ${GPU_NIC}
  
  # Get the GPU
  # TODO: NV needs to be a substring, but it probably won't come up much
  CONNECTION_PRIORITY=( "NV" "PIX" "PXB" "PHB" "NODE" "SYS" )
  CONNECTION_LIST=$(nvidia-smi topo -m | grep "^${GPU_NIC}" | tr '\t' ' ' ) 
  #echo ${CONNECTION_LIST}
  for PRIORITY in ${CONNECTION_PRIORITY[@]}; do
      GPU=$(get_gpu_priority "${PRIORITY} ") 
      #echo ${GPU}
      if [ "${GPU}" != "" ]; then
        echo ${NET_DEV} best GPU link = ${PRIORITY}
	echo ${NET_DEV} best GPU = CUDA device ${GPU}
        break
      fi
  done

echo " " 
done 