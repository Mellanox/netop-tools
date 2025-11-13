#!/bin/bash
#
#
rm -f /etc/machine-id
systemd-machine-id-setup
reboot
