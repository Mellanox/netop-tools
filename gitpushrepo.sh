#!/bin/bash -x
#
# for the current commits:
#  create a branch
#  checkout the branch
#  push the commits
#
if [ $# -ne 2 ];then
  echo "usage:$0 {dest repo} {push branch}"
  exit 1
fi
git branch ${2}
git checkout ${2}
git push -u ${1} ${2}
