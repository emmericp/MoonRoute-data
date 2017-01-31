#!/bin/bash

# this script takes ~ 4 hours to run
# change some loops to make it go faster
(
echo "WRITE rt.flush"
# required becaus of the simplified tx path without ARP and no IP on the tx interface
echo "WRITE rt.add 10.1.0.10/32 1"
for a in `seq 1 16`; do
	for b in `seq 0 255`; do
		echo "WRITEUNTIL rt.ctrl EOF"
		for c in `seq 0 255`; do
	 	  	echo "add $a.$b.$c.1/24 10.1.0.10 1"
		done
		echo "EOF"
	done
done
) | nc localhost 12345
