#!/usr/bin/bash
# Build cuda-perftest in rdma debug container
apt-get update
apt-get -y install libibumad-dev
apt-get -y install pciutils
apt-get -y install libpci-dev

cd /root/perftest
autoupdate
./autogen.sh
./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h
make
make install
