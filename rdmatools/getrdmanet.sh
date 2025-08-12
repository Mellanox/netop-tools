#!/bin/bash
#
#
NET=${1}
shift
LINE=$(ip -br a | grep ${NET} | tr -s [:space:])
DEV=$(echo ${LINE}| cut -d' ' -f1)
GID=$(echo ${LINE}| cut -d' ' -f2)
echo ${DEV},${GID}
