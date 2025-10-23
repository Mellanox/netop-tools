#!/bin/bash
# must be root to access extended PCI config space
if [ "$EUID" -ne 0 ]; then
 echo "ERROR: $0 must be run as root"
 exit 1
fi
for BDF in `lspci -d "*:*:*" | awk '{print $1}'`; do
  # skip if it doesn't support ACS
  setpci -v -s ${BDF} ECAP_ACS+0x6.w > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    # echo "${BDF} does not support ACS, skipping"
    continue
  fi
  logger "Disable ACS on `lspci -s ${BDF}`"
  setpci -v -s ${BDF} ECAP_ACS+0x6.w
  setpci -v -s ${BDF} ECAP_ACS+0x6.w=0x0
  setpci -v -s ${BDF} ECAP_ACS+0x6.w
  if [ $? -ne 0 ]; then
    logger "Error disabling ACS on ${BDF}"
    continue
  fi
  NEW_VAL=`setpci -v -s ${BDF} ECAP_ACS+0x6.w | awk '{print $NF}'`
  if [ "${NEW_VAL}" != "0x0" ]; then
    logger "Failed to Disable ACS on ${BDF}"
    continue
  fi
done
exit 0
