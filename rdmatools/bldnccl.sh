#!/bin/bash
TAG="v2.28.7-1"
function pkgs()
{
  apt install -y build-essential devscripts debhelper fakeroot
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
  ls build/pkg/deb/
}
pkgs
getsrc
cd ./nccl
makesrc
mkpkg
