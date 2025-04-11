#!/bin/bash
#
#
function nsReady()
{
  READY=0
  while [ "${READY}" = "0" ];do
    READY=1
    for POD in ${PODLIST[@]};do
      read CNT NS NAME <<< ${POD//,/ }
      RCNT=`${K8CL} get pods -n ${NS} | tr -s [:space:] | cut -d' ' -f1,3 | grep "${NAME}" | grep -c Running`
      if [ "${RCNT}" -lt "${CNT}" ];then
        READY=0
        echo "Waiting for $CNT instances of pod $NAME in $NS namespace. Currently ready: $RCNT"
        break
      fi
    done
    if [ "${READY}" = "0" ];then
      sleep 10
    fi
  done
  echo "READY"
}
