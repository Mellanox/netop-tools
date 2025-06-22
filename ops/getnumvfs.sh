#!/bin/bash
#
# get the VFs setting for Mellanox NICs
#
DEVS=$(lspci | grep Mel | grep -v Virt | grep ConnectX | cut -d' ' -f1)
VARS=( sriov_numvfs mlx5_num_vfs sriov_totalvfs )
HAS_IOMMU=$(grep -c iommu /proc/cmdline)
if [ "${HAS_IOMMU}" != "0" ];then
  echo "system has iommu setting in:/proc/cmdline"
else
  echo "system missing iommu setting in /proc/cmdline"
fi
for DEV in ${DEVS};do
  echo "${DEV} mlxconfig setting:"$(mlxconfig -d ${DEV} q | egrep 'SRIOV_EN|NUM_OF_VFS')
  for VAR in ${VARS[@]};do
    PATHVFS=$(find /sys/devices -name ${VAR} | grep "${DEV}" )
    NUMVFS=$(cat ${PATHVFS})
    echo "${PATHVFS}=${NUMVFS}"
  done
done
