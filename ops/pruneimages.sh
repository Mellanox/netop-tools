#!/bin/bash
#
# prune out exited contaniners, and non-referenced images
#
(
CONTAINERS=$(crictl ps -a | grep "Exited" | tr -s [:space:] | cut -d' ' -f1)
echo "CONTAINERS:${#CONTAINERS[@]}"
for CONTAINER in ${CONTAINERS[@]};do
  echo "CONTAINER:${CONTAINER}"
  crictl rm ${CONTAINER}
done
IMAGES=$(crictl images | grep "<none>" | tr -s [:space:] | cut -d' ' -f3)
echo "IMAGES:${#IMAGES[@]}"
for IMAGE in ${IMAGES[@]};do
  echo "IMAGE:${IMAGE}"
  crictl rmi ${IMAGE}
done
) 2>/dev/null
