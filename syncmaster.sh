#!/bin/bash
#
# push the devbranch to dev repo
# synch the repos
#
if [ $# -lt 2 ];then
  echo "usages:$0 {devbranch} {commit comment}"
  exit 1
fi
git commit -m "${2}"
./gitpushrepo.sh dev ${1}
./syncrepo.sh dev origin master
git push
git checkout master
git pull
./syncrepo.sh dev origin master
