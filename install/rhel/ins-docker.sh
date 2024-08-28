#!/bin/bash
#
#
#
function setup()
{
dnf update
dnf install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
}
#
# Install Docker Engine
# Update the package index:
#
setup
yum install -y yum-utils
yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
echo "expected key:060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35"
dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
#docker run hello-world
systemctl enable docker
systemctl start docker
