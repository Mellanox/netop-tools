#!/bin/bash
# install go
#
#dnf install -y golang-go
# https://go.dev/dl/
FILE="go1.22.6.linux-amd64.tar.gz"
wget https://go.dev/dl/${FILE}
tar -xvf ${FILE}
