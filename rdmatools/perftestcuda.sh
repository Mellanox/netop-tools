#!/bin/bash
#
# https://confluence.nvidia.com/display/support/Perftest+with+CUDA+Support
#
cd /root
apt -get install -y libibumad-dev libibumad3 libibumad
git clone https://github.com/linux-rdma/perftest.git
pushd .
cd perftest
export LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export CUDA_H_PATH="/usr/local/cuda/include/cuda.h"
./autogen.sh
./configure --prefix=/usr --sbindir=/usr/bin --libexecdir=/usr/lib --sysconfdir=/etc --localstatedir=/var --mandir=/usr/share/man
make -j "$(($(nproc) + 1))"
make install
popd
source /root/perftestenv.sh
./install_perftest_cuda.sh
