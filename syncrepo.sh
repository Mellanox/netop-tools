#!/bin/bash
#
# sync dev repo into origin repo on specified branch
#
# Fetch the changes from the first repository and push to the second
if [ $# -ne 3 ];then
  echo "usage:$0 srcrepo destrepo branch"
  echo "$0 {dev} {origin} master"
  exit
fi
# Use the git fetch command to fetch the changes from the second repository.
git fetch ${1}
# Merge the changes: If you want to merge the changes from the second repository into the first,
# you can use the git merge command.
# This will merge the changes from the main (or master) branch of ${1} into the main (or master) branch of repo1.
git merge ${1}/${3}
# Push the changes:
# Finally, use the git push command to push the changes back to the first repository on GitHub.
git push ${2} ${3}
