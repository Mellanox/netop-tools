#!/bin/bash
if [ $# -lt 1 ];then
  echo "usage:$0 NUM_OF_VFS"
  exit 1
fi
for DEV in $(cat tmp.1);do
  sudo mlxconfig -d ${DEV} -y set NUM_OF_VFS=${1}
done
