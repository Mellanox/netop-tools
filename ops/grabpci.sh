#!/bin/bash
#
# grab PCI addresses of device type
#
DEV=${1:-"ConnectX7"}
if [ -lt 1 ];then
  echo "useage:$0 {Connectx8|ConnectX7|Connect6Dx|BF3}"
  echo "using default ${DEV}"
fi
PCIS=$(sudo mst status -v | grep "${DEV}" | tr -s [:space:] | cut -d' ' -f 3)
for PCI in ${PCIS[@]};do
        echo "a,,,0000:${PCI} "
done
