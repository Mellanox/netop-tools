#!/bin/bash
#
# Commit the changes made to the running container and create a new image
#
nerdctl --namespace=k8s.io commit ${1} ${2}

# Save the image to a local file
nerdctl --namespace=k8s.io image save ${2} -o ${2}.tar
exit 0
# Tag the image with the target registry information
nerdctl --namespace=k8s.io tag ${2} my-registry.com/${2}:latest

# Push the image to the target registry
nerdctl --namespace=k8s.io push my-registry.com/${2}:latest
