#!/bin/bash
#cmsh -c 'device; pexec -c dgx-h100 -j "for I in 0 3 4 5 6 9 10 11; do for X in 0 1 2 3 4 5 6 7: do K=$(printf $((i*10+x)) ); echo 00:11:22:33:44:55:$K:$K > /sys/class/infiniband/mlx5_$i/device/sriov/$x/node; done"'
for I in 0 3 4 5 6 9 10 11; do for X in 0 1 2 3 4 5 6 7; do K=$(printf $((I*5+X)) ); echo 00:11:22:33:44:55:$K:$K > /sys/class/infiniband/mlx5_$I/device/sriov/$X/node ; done; done
