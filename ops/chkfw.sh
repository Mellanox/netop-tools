#!/bin/bash
#
#
for DEV in $(sudo lspci | grep Mel | grep -i "Connectx-7" | cut -d' ' -f1);do
  echo "DEV:${DEV}";sudo flint -d ${DEV} q full | egrep "Version|Release"
done
