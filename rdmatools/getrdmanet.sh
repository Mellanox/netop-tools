#!/bin/bash
#
#
function getProtocol()
{
if [ $(grep -c v2 gid_info.$$) != 0 ];then
  echo "v2"
else
  echo "v1"
fi
}
function getPartGUID()
{
  LINE=$(ip -br a | grep ${1} | tr -s [:space:])
  DEV=$(echo ${LINE}| cut -d' ' -f1)
  IP=$(echo ${LINE}| cut -d' ' -f3 | cut -d'/' -f1)
  GUID_RAW=$(echo ${LINE}| cut -d' ' -f4| cut -d':' -f4-6| cut -d'/' -f1)
  IFS=':' read -ra PARTS <<< "${GUID_RAW}"
  GUID=$(printf "%04x:%04x:%04x" $((16#${PARTS[0]})) $((16#${PARTS[1]})) $((16#${PARTS[2]})))
  echo ${DEV},${GUID},${IP}
}
function getAzure()
{
  LINE=$(getPartGUID ${1})
  IP=$(echo ${LINE}|cut -d',' -f3)
  GUID=$(echo ${LINE}|cut -d, -f2)
  /root/show_gids > gid_info.$$
  PROTOCOL=$(getProtocol)
  GLINE=$(/root/show_gids |grep ${GUID}|grep ${PROTOCOL}|tr -s [:space])
  DEV=$(echo ${GLINE}|cut -d' ' -f1)
  GID=$(echo ${GLINE}|cut -d' ' -f3)
  echo ${DEV},${GID},${IP},${1}
  # rm -f gid_info.$$
}
function getDGX()
{
  LINE=$(ip -br a | grep ${1} | tr -s [:space:])
  DEV=$(echo ${LINE}| cut -d' ' -f1)
  IP=$(echo ${LINE}| cut -d' ' -f2)
  GID=$(echo ${LINE}| cut -d' ' -f3)
  echo ${DEV},${GID},${IP},${1}
}
if [ "$#" -eq 1 ];then
  getAzure ${1}
else
  ip -br a | grep net | tr -s [:space:] | while read LINE;do
    NET=$(echo ${LINE} | cut -d' ' -f1)
    getAzure ${NET}
  done
fi
