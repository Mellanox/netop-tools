#!/bin/bash
#
# global env vars for ngc private registry
#
NGC=$(which ngc)
if [ "${NGC}" = "" ];then
  export PATH=${PATH}:$(pwd)/ngc-cli
  NGC=$(which ngc)
fi
