#!/bin/bash
#
#
while [ "1" ];do
  #X=`crictl ps -a 2>/dev/null | grep -v "GracePeriod" | grep 'mofed-container' | grep -c 'Running'`
  X=`crictl ps -a 2>/dev/null | grep 'mofed-container' | grep -c 'Running'`
  if [ "${X}" = "1" ];then
    break
  fi
done
X=`crictl ps -a 2>/dev/null | grep 'mofed-container' | tr -s [:space:] `
X=`echo ${X} | cut -d' ' -f1`
echo ${X}
crictl exec -it ${X} bash
