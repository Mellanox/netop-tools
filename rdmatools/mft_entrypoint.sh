#!/bin/bash
#
# mft install must be done at container launch
# because mft is dependent on the host kernel
# not the build system kernel
#
function install_mft()
{
  cd /root/payloads
  apt-get install -y dkms linux-headers-$(uname -r) linux-headers-generic
  TARBALL=$(ls | grep mft )
  DIR=$(echo ${TARBALL} | sed 's/.tgz//')
  tar -xvf ${TARBALL}
  cd ${DIR}
  ./install.sh --oem
  cd /root
}
install_mft
echo "NVIDIA mft container sleeping"
sleep infinity & wait
