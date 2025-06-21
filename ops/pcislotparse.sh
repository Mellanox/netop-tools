#!/bin/bash 
#
#
STATE=0
DMIDECODE="/tmp/dmidecode.$$"
dmidecode | tr -s [:space:] > ${DMIDECODE}
declare -A SLOTLST
function slotmap()
{
  while read -u 3 LINE;do
    case ${STATE} in
    0)
      if [ `echo ${LINE} | grep -c "System Slot Information"` = "1" ];then
        STATE=1
        #echo ${LINE}
      fi
      ;;
    1)
      if [ `echo ${LINE} | grep -c "Designation: PCIe Slot"` = "1" ];then
	STATE=2
        SLOT=`echo ${LINE} | cut -d' ' -f4`
      elif [ `echo ${LINE} | grep -c "ID:"` = "1" ];then
        STATE=2
        SLOT=`echo ${LINE} | cut -d' ' -f2`
      fi
      ;;
    2)
      if [ `echo ${LINE} | grep -c "Bus Address:"` = "1" ];then
        STATE=0
        PCIADDR=`echo ${LINE} | cut -d' ' -f3`
	PCIBD=`echo ${PCIADDR}|cut -d ':' -f2-3 | cut -d':' -f1`
        SLOTLST["${PCIBD}"]="${PCIADDR},${SLOT}"
      fi
      ;;
    esac
  done 3< ${DMIDECODE}
  rm -f ${DMIDECODE}
#  for DEV in ${SLOTLST[@]};do
#    echo ${DEV}
#  done
}
slotmap
NICS=`lspci -d 15b3:|tr -s [:space:] | cut -d' ' -f1`
for NIC in ${NICS[@]};do
  NICBD=`echo ${NIC}|cut -d':' -f1`
  SLOT=${SLOTLST[${NICBD}]}
  PCIADDR=`echo ${SLOT}|cut -d, -f1`
  if [ "${PCIADDR}" != "" ];then
    NUMA=`lspci -v -d 15b3: -s ${PCIADDR}| tr -s [:space:]  | grep -i numa | sed 's/.*NUMA/NUMA/'| cut -d' ' -f3`
  elif [ "${NIC}" != "" ];then
    NUMA=`lspci -v -d 15b3: -s ${NIC}| tr -s [:space:]  | grep -i numa | sed 's/.*NUMA/NUMA/'| cut -d' ' -f3`
  else
	NUMA=""
  fi
  NETDEV=`ls "/sys/bus/pci/drivers/mlx5_core/0000:${NIC}/net"`
  RDMADEV=`ls "/sys/bus/pci/drivers/mlx5_core/0000:${NIC}/infiniband"`
  echo ${NIC},${SLOT},${NETDEV},${RDMADEV},${NUMA}
done
