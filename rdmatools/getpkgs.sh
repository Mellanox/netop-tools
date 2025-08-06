#!/bin/bash
#
# get prebuilt packages
#
apt-get update
apt-get install -y git libtool autotools-dev automake autoconf m4 flex bison gawk
apt-get install -y libibverbs-dev librdmacm-dev vim
apt-get install -y libcap2-bin infiniband-diags iproute2 ibverbs-utils iputils-ping
apt-get install -y net-tools traceroute dnsutils tcpdump kmod
# mft
