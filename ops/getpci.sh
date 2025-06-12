#!/bin/bash
# ignore VFs
# ${1} pattern
if [ $# -ne 1 ];then
  echo "usage:$0 {nic name pattern}"
  exit 1
fi
lspci | grep Mel | grep -v Virtual | grep "${1}" | cut -d' ' -f1
