#!/bin/bash
#
#
function getPartGUID()
{
  LINE=$(ip -br a | grep ${NET} | tr -s [:space:])
  DEV=$(echo ${LINE}| cut -d' ' -f1)
  IP=$(echo ${LINE}| cut -d' ' -f3 | cut -d'/' -f1)
  GUID=$(echo ${LINE}| cut -d' ' -f4| cut -d':' -f4-6| cut -d'/' -f1)
  echo ${DEV},${GUID},${IP}
}
function getAzure()
{
  LINE=$(getPartGUID)
  IP=$(echo ${LINE}|cut -d',' -f3)
  GUID=$(echo ${LINE}|cut -d, -f2)
  GLINE=$(/root/show_gids |grep ${GUID}|tr -s [:space])
  DEV=$(echo ${GLINE}|cut -d' ' -f1)
  GID=$(echo ${GLINE}|cut -d' ' -f3)
  echo ${DEV},${GID},${IP}
}
function getDGX()
{
  LINE=$(ip -br a | grep ${NET} | tr -s [:space:])
  DEV=$(echo ${LINE}| cut -d' ' -f1)
  IP=$(echo ${LINE}| cut -d' ' -f2)
  GID=$(echo ${LINE}| cut -d' ' -f3)
  echo ${DEV},${GID},${IP}
}
NET=${1}
shift
getAzure
