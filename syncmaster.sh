#!/bin/bash
#
# push the devbranch to dev repo
# synch the repos
#
if [ $# -lt ${1} ];then
  echo "usages:$0 {devbranch}"
  exit 1
fi
./gitpushrepo.sh dev ${1}
./syncrepo.sh dev origin master
git push
git checkout master
git pull
./syncrepo.sh dev origin master
