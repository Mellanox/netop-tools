#!/bin/bash
#
#
modprobe br_netfilter
sysctl net.bridge.bridge-nf-call-ip6tables=1
sysctl net.bridge.bridge-nf-call-iptables=1
sysctl net.ipv4.ip_forward=1
sysctl net.ipv6.ip_forward=1
