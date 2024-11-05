#!/bin/bash
#
# get prebuilt packages
#
apt-get update
apt-get install -y git libtool autotools-dev automake autoconf m4 flex bison
apt-get install -y libibverbs-dev librdmacm-dev
apt-get install -y libcap2-bin infiniband-diags iproute2 ibverbs-utils iputils-ping
