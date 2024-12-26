#!/bin/bash
#
# https://confluence.nvidia.com/display/support/How+to+enable+the+sniffer+for+RDMA+device+-+Linux
#
cd /root
apt-get install -y libnl3* git
git clone https://github.com/the-tcpdump-group/libpcap.git
cd libpcap/
./autogen.sh
./configure --enable-rdma --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib64
make -j 8
make install
