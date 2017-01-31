#!/bin/bash
# build fastclick, we used commit 8f3cd4fe6e85fcbe0c07fa2e15a7457d8a1af733
# perform the usual incantations to make DPDK work (hugetlbfs, kernel module, drivers, CLI arguments)
./configure --enable-multithread --disable-linuxmodule --enable-intel-cpu --enable-user-multithread --verbose CFLAGS="-g -O3" CXXFLAGS="-g -std=gnu++11 -O3" --disable-dynamic-linking --enable-poll --enable-bound-port-transfer --enable-dpdk --enable-batch --with-netmap=no --enable-zerocopy --enable-dpdk-pool --disable-dpdk-packet
make -j8
