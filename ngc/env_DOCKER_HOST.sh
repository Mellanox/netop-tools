#!/bin/bash
#
# set DOCKER_HOST env variable for docker->podman mapping
#
if [[ $(uname -a) = *"microsoft-standard-WSL2"* ]]; then
  PODMAN=$(which podman)
  if [ "${PODMAN}" != "" ];then
    SOCKET=$(podman info --format '{{.Host.RemoteSocket.Path}}')
    export DOCKER_HOST=unix://${SOCKET}
  fi
fi
