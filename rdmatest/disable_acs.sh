#!/bin/bash
#
# now filtering for Mellanox NICs and NVIDIA GPUs
# turning off the NIC/GPU pairs
# and the PCIe bridge that is above NIC/GPU pairs
#
# pass in the NIC/GPU BDF device list,
# since there can be NICs which aren't part of E/W traffic
# if no device list provided, create 1
#
function getBridge()
{
  PCI=$(lspci -D | grep ":${1} ")
  BUS=$(echo ${PCI}| cut -d':' -f2)
  DF=$(echo ${PCI}| cut -d':' -f3| cut -d' ' -f1)
  DEV=$(echo ${DF} | cut -d'.' -f1)
  FUNC=$(echo ${DF} | cut -d'.' -f2)
  #lspci -v | grep "Bus: primary=00, secondary=${BUS}"
  BRIDGE_LINE=$(lspci -v | grep "Bus:" | grep "secondary=${BUS}" | tr -s [:space])
  BRIDGE=$(echo ${BRIDGE_LINE} | cut -d' ' -f2 | cut -d',' -f1 | cut -d'=' -f2)
  BRIDGE_BDF=$(lspci | grep "^${BRIDGE}:" | grep -i bridge | cut -d' ' -f1)
  echo "${BRIDGE_BDF}"
}
function disableACS()
{
  PCI=$(lspci -s ${1})
  # skip if it doesn't support ACS
  setpci -v -s ${1} ECAP_ACS+0x6.w > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    logger "${PCI} does not support ACS, skipping"
    return 1
  fi
  logger "Disabling ACS on ${PCI}"
  setpci -v -s ${1} ECAP_ACS+0x6.w > /dev/null 2>&1
  setpci -v -s ${1} ECAP_ACS+0x6.w=0x0 > /dev/null 2>&1
  setpci -v -s ${1} ECAP_ACS+0x6.w > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    logger "Error disabling ACS on ${PCI}"
    return 1
  fi

  NEW_VAL=`setpci -v -s ${1} ECAP_ACS+0x6.w | awk '{print $NF}'`
  #
  # previously this was testing for 0x0.
  # but ECAP_ACS+0x6.w returns 0000
  #
  if [ "${NEW_VAL}" != "0000" ]; then
    logger "${NEW_VAL}:Failed to Disable ACS on ${PCI}"
  else
    logger "Disabled ACS on ${PCI}"
  fi
  return 0
}
function NIC_GPU_LST()
{
  lspci -d "*:*:*" | egrep 'Mellanox|3D controller' | grep -v Virtual | awk '{print $1}'
}
PLATFORM=$(dmidecode --string system-product-name)
logger "PLATFORM=${PLATFORM}"

# must be root to access extended PCI config space
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: $0 must be run as root"
  exit 1
fi

if [ $# -lt 1 ];then
  # look for Mellanox NICs and GPUs
  BDF_LST=$(NIC_GPU_LST)
else
  # use passed in list
  BDF_LST=$*
fi
for BDF in ${BDF_LST}; do
  disableACS ${BDF}
  if [ $? -eq 0 ];then
    BRIDGE=$(getBridge ${BDF})
    disableACS ${BRIDGE}
  fi
done
exit 0 
