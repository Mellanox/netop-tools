#!/bin/bash
TAG="v2.28.7-1"
function pkgs()
{
  apt-get update
  apt install -y build-essential devscripts debhelper fakeroot lintian
  apt install -y openmpi-bin libopenmpi-dev openssh-server
  #mkdir -p /run/sshd && chmod 755 /run/sshd && ssh-keygen -A
}
function getsrc()
{
  git clone https://github.com/NVIDIA/nccl
  cd ./nccl
  git checkout "tags/${TAG}" -b "${TAG}"
}
function makesrc()
{
  make -j src.build NVCC_GENCODE="-gencode=arch=compute_110,code=sm_110" # CUDA13
}
# Build NCCL deb package
function mkpkg()
{
  make pkg.debian.build
  cd /root/nccl/build/pkg/deb
  FILES=""
  for FILE in $(ls *.deb);do
    FILES="${FILES} ./${FILE}"
  done
  apt install -y --allow-change-held-packages ${FILES}
}
function mktests()
{
 git clone https://github.com/NVIDIA/nccl-tests.git
 cd nccl-tests
 make -j src.build
}
cd /root
pkgs
getsrc
pushd .
cd ./nccl
makesrc
mkpkg
popd
mktests
