#!/bin/bash
#
#
NET=${1}
shift
LINE=$(ip -br a | grep ${NET} | tr -s [:space:])
DEV=$(echo ${LINE}| cut -d' ' -f1)
IP=$(echo ${LINE}| cut -d' ' -f3 | cut -d'/' -f1)
GUID=$(echo ${LINE}| cut -d' ' -f4)
GUID=$(echo ${GUID} | cut -d'/' -f1)
GUID=$(echo ${GUID} | cut -d':' -f4,5,6)
LINE=$(show_gids | grep ${GUID})
DEV=$(echo ${LINE} | cut -d' ' -f1)
GID=$(echo ${LINE} | cut -d' ' -f2)
echo ${DEV},${GID},${IP}