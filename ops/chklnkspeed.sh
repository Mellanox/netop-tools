#!/bin/bash
#
#
for DEV in $(sudo lspci | grep Mel | grep -i "Connectx-7" | cut -d' ' -f1);do
  echo "DEV:${DEV}";sudo mlxlink -d ${DEV} | egrep "State|Physical state|Auto|Speed"
done
