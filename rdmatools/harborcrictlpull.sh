#!/bin/bash
#
# --creds "{username}:{password}"
#
sudo crictl pull --creds "${1}:${2} harbor.runailabs-ps.com/nvidia/rdmadbg_cuda:latest
