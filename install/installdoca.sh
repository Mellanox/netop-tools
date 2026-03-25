#!/bin/bash
#
#
DOCAVER="3.2.0"
OSVER="ubuntu22.04"
function install_arm64()
{
export DOCA_URL="https://linux.mellanox.com/public/repo/doca/${DOCAVER}/${OSVER}/arm64-sbsa/"
BASE_URL=$([ "${DOCA_PREPUBLISH:-false}" = "true" ] && echo https://doca-repo-prod.nvidia.com/public/repo/doca || echo https://linux.mellanox.com/public/repo/doca)
DOCA_SUFFIX=${DOCA_URL#*public/repo/doca/}; DOCA_URL="$BASE_URL/$DOCA_SUFFIX"
curl $BASE_URL/GPG-KEY-Mellanox.pub | gpg --dearmor > /etc/apt/trusted.gpg.d/GPG-KEY-Mellanox.pub
echo "deb [signed-by=/etc/apt/trusted.gpg.d/GPG-KEY-Mellanox.pub] $DOCA_URL ./" > /etc/apt/sources.list.d/doca.list
apt-get update
apt-get -y install doca-ofed
}
function install_x86()
{
export DOCA_URL="https://linux.mellanox.com/public/repo/doca/${DOCAVER}/${OSVER}/x86_64/"
BASE_URL=$([ "${DOCA_PREPUBLISH:-false}" = "true" ] && echo https://doca-repo-prod.nvidia.com/public/repo/doca || echo https://linux.mellanox.com/public/repo/doca)
DOCA_SUFFIX=${DOCA_URL#*public/repo/doca/}; DOCA_URL="$BASE_URL/$DOCA_SUFFIX"
curl $BASE_URL/GPG-KEY-Mellanox.pub | gpg --dearmor > /etc/apt/trusted.gpg.d/GPG-KEY-Mellanox.pub
echo "deb [signed-by=/etc/apt/trusted.gpg.d/GPG-KEY-Mellanox.pub] $DOCA_URL ./" > /etc/apt/sources.list.d/doca.list
apt-get update
apt-get -y install doca-ofed
}
case "${1}" in
x86)
  install_x86
  ;;
arm64)
  install_arm64
  ;;
*)
  echo "usage $0 {x86|arm64}"
  exit 1
esac
