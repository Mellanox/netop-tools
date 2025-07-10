#!/bin/bash
echo "SYSCTL_CONFIG:${SYSCTL_CONFIG}"
IFS=',' read SYSVALS <<< ${SYSCTL_CONFIG}
for SYSVAL in ${SYSVALS};do
  sysctl ${SYSVAL}
done
echo "NVIDIA rdmadbg_cuda container sleeping"
sleep infinity & wait
