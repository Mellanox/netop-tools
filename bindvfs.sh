#!/bin/bash
#
#
modprobe mlx5_core
./setvfs.sh 4 0000:65:00.1 0000:e4:00.1 
#VFS=$(lspci | grep Virt | grep -i "65:" | cut -d' ' -f1 ) $(lspci | grep Virt | grep -i "e4:" | cut -d' ' -f1 )
#VFS=( 0000:65:00.6 0000:65:00.7 0000:65:01.0 0000:65:01.1 0000:e4:00.6 0000:e4:00.7 0000:e4:01.0 0000:e4:01.1 )
function dobind()
{
for d in ${VFS[@]}; do
  d="0000:${d}"
  echo "=== $d ==="
  echo "" > /sys/bus/pci/devices/$d/driver_override
  if [ -L /sys/bus/pci/devices/$d/driver ]; then
    echo $d > /sys/bus/pci/devices/$d/driver/unbind
  fi
  echo mlx5_core > /sys/bus/pci/devices/$d/driver_override
  echo $d > /sys/bus/pci/drivers_probe
done

# Then verify:

for d in ${VFS[@]}; do
  d="0000:${d}"
  echo "=== $d ==="
  basename "$(readlink /sys/bus/pci/devices/$d/driver 2>/dev/null)" || echo "NO
  DRIVER"
  ls /sys/bus/pci/devices/$d/net 2>/dev/null || echo "NO NETDEV"
  ls /sys/bus/pci/devices/$d/infiniband 2>/dev/null || echo "NO RDMADEV"
done
}
VFS=$(lspci | grep Virt | grep -i "65:" | cut -d' ' -f1 ) 
dobind
VFS=$(lspci | grep Virt | grep -i "e4:" | cut -d' ' -f1 )
dobind
