#!/bin?bash
#
# kill pts left over on system
#
for TERM in $*;do
  PID=$(ps -ft ${TERM} | grep -v PID | tr -s [:space:] | cut -d' ' -f2 )
  echo ${TERM}:${PID}
  kill -9 ${PID}
done
