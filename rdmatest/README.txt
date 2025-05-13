1. disable_acs.sh (to be run on the b200 bare metal machines) @Marina Varshaver
2. K8s_netdev_mapping.sh (to be run inside the perftest-debug pod to print out the vf / gpu mapping)
3. ../rdmatools/install_perftest_cuda.sh (to be run inside the pertest-debug pods to compile perftest with cuda)
4. gdrserver.sh (run server RDMA ib_write_bw test using GPU)
5. gdrclient.sh (run client RDMA ib_write_bw test using GPU)

