#!/bin/bash
#
#
#
if [ $# -ne 1 ];then
  echo "usage:$0 {push branch}"
  exit 1
fi
git push -u origin ${1}
