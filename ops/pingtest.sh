#!/bin/bash
#
#
if [ $# -ne 2 ];then
	echo "usage:$0 SRC_LSB DST_LSB"
	exit 1
fi
SRCNODE=${1}
shift
DSTNODE=${1}
shift
DEVLST=$(ip -br a  | grep ${SRCNODE} | grep rdma | tr -s [:space:] | cut -d' ' -f1 )
for DEV in ${DEVLST[@]};do
  IP=$(ip -br a show dev ${DEV}|tr -s [:space:] | cut -d' ' -f3 | cut -d'/' -f1)
  echo "${DEV}:${IP}"
  DSTIP=$(echo ${IP} | sed 's/'${SRCNODE}'/'${DSTNODE}'/')
  ping ${DSTIP} -I ${DEV} -c 4
done
