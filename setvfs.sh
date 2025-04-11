#!/bin/bash
#
# run on the worker nodes
#
NUMVFS=${1}
shift
for BDF in ${*};do
  VFPATH=`find /sys -name sriov_numvfs | grep "${BDF}"`
  echo "VFPATH:${VFPATH}"
  if [ "${VFPATH}" != "" ];then
    echo "${NUMVFS}" > ${VFPATH}
  else
    echo "WARNING:Not Found:${BDF}"
  fi
done
