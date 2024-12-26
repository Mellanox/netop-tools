#!/bin/bash
#
# https://github.com/Mellanox/mlnx-tools
#
cd /root
apt-get install -y git
git clone https://github.com/Mellanox/mlnx-tools
mv /root/mlnx-tools/sbin/show_gids /usr/bin
mv /root/mlnx-tools/python/mlnx_qos /usr/bin
