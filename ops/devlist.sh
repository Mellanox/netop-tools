#!/bin/bash
#
#
DEVLST=$(ip -br a  | grep rdma | grep -v v | tr -s [:space:] | cut -d' ' -f1 )
for DEV in ${DEVLST[@]};do
  IP=$(ip -br a show dev ${DEV}|tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1)
  echo "${DEV}:${IP}"
done
