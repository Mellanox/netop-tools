#!/bin/bash
#
#
#
source "${NETOP_ROOT_DIR}/global_ops.cfg"
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker’s official GPG key:
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
#
# Use the following command to set up the repository:
#
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
#
# Install Docker Engine
# Update the apt package index:
#
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl restart docker
docker run hello-world
