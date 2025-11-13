#!/bin/bash
#
#
cat << HEREDOC
in /etc/netplan/50-cloud-init.yaml
under the option
  dhcp4: true
add the option
  dhcp-identifier: mac
to force MAC based DHCP assignment
HEREDOC
rm -f /etc/machine-id
systemd-machine-id-setup
reboot
