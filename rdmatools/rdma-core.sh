#!/bin/bash
#
# https://github.com/linux-rdma/rdma-core
#
apt-get install -y build-essential cmake gcc libudev-dev libnl-3-dev libnl-route-3-dev ninja-build pkg-config valgrind python3-dev cython3 python3-docutils pandoc git
cd /root
git clone https://github.com/linux-rdma/rdma-core
cd rdma-core
bash /root/rdma-core/build.sh
#
# set up software RDMA on an existing interface with either of the available drivers,
# use the following commands, substituting <DRIVER> with the name of the driver
# of your choice (rdma_rxe or siw) and <TYPE> with the type corresponding to the driver (rxe or siw).

# modprobe <DRIVER>
# rdma link add <NAME> type <TYPE> netdev <DEVICE>

