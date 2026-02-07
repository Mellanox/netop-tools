#!/bin/bash
# 1. Enable and sync
echo 1 > /proc/sys/kernel/sysrq
echo "Syncing filesystems..."
echo s > /proc/sysrq-trigger
sleep 5

# 2. Remount read-only
echo "Remounting read-only..."  
echo u > /proc/sysrq-trigger
sleep 3

# 3. Force reboot
echo "Rebooting now..."
echo b > /proc/sysrq-trigger
