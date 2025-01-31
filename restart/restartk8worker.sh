#!/bin/bash
#
#
#
sudo kubeadm reset
swapoff -a
sudo systemctl enable docker
sudo systemctl enable kubelet
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo netstat -lnp | grep 1025
sudo rm -rf /etc/kubernetes/kubelet.conf /etc/kubernetes/pki/ca.crt  /etc/cni/net.d
