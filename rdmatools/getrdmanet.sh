#!/bin/bash
#
#
NET=${1}
shift
LINE=$(ip -br a | grep ${NET} | tr -s [:space:])
DEV=$(echo ${LINE}| cut -d' ' -f1)
IP=$(echo ${LINE}| cut -d' ' -f2)
GID=$(echo ${LINE}| cut -d' ' -f3)
echo ${DEV},${GID},${IP}
