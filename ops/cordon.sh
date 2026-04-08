#!/bin/bash
#
# "cordon the worker nodes"
#
function cordon()
{
  while IFS= read -r NODE; do
    echo "cordon ${NODE}"
    ${K8CL} cordon "${NODE}"
  done < <(${K8CL} get nodes --no-headers | grep worker | grep -v 'control-plane' | grep -v SchedulingDisabled | awk '{print $1}')
}
#
# "uncordon the worker nodes"
#
function uncordon()
{
  while IFS= read -r NODE; do
    echo "uncordon ${NODE}"
    ${K8CL} uncordon "${NODE}"
  done < <(${K8CL} get nodes --no-headers | grep worker | grep -v 'control-plane' | grep SchedulingDisabled | awk '{print $1}')
}
