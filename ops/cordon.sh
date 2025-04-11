#!/bin/bash
#
# "cordon the worker nodes"
#
function cordon()
{
  NODES=`${K8CL} get nodes | grep worker | grep -v SchedulingDisabled | cut -d' ' -f1`
  for NODE in ${NODES};do
    echo "cordon ${NODE}"
    ${K8CL} cordon ${NODE}
  done
}
#
# "uncordon the worker nodes"
#
function uncordon()
{
  NODES=`${K8CL} get nodes | grep worker | grep SchedulingDisabled | cut -d' ' -f1`
  for NODE in ${NODES};do
    echo "uncordon ${NODE}"
    ${K8CL} uncordon ${NODE}
  done
}
