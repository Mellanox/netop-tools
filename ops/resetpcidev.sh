#!/bin/bash
#
# remove and rescan PCI device
#
echo 1 > /sys/bus/pci/devices/${1}/remove
sleep 1
echo 1 > /sys/bus/pci/rescan
