#!/bin/bash
#
# sync devi repo into origin repo
#
# Fetch the changes from the second repository: dev
# Use the git fetch command to fetch the changes from the second repository.
git fetch dev
# Merge the changes: If you want to merge the changes from the second repository into the first,
# you can use the git merge command.
# This will merge the changes from the main (or master) branch of dev into the main (or master) branch of repo1.
git merge dev/main
# Push the changes:
# Finally, use the git push command to push the changes back to the first repository on GitHub.
git push origin main
