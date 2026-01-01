#!/bin/bash
#
#
#
# On control plane
sudo iptables -L INPUT -n -v | head -20
sudo iptables -L FORWARD -n -v | head -20

# Check for any DROP rules
sudo iptables -S | grep -i drop
