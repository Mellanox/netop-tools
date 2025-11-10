#!/bin/bash -x
#
# pull images from ./container/{VERSION} file list
#
cat ${1} | while read LINE;do
	REGISTRY=$(echo ${LINE}|cut -d',' -f3)
	IMAGE=$(echo ${LINE}|cut -d',' -f4)
	TAG=$(echo ${LINE}|cut -d',' -f5)
	crictl pull ${REGISTRY}/${IMAGE}:${TAG}
done
