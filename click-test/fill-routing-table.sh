#!/bin/bash

# this script takes > 12 hours to run
# change some loops to make it go faster
(
echo "WRITE rt.flush"
for a in `seq 0 63`; do
	for b in `seq 0 255`; do
		echo "WRITEUNTIL rt.ctrl EOF"
		for c in `seq 0 255`; do
	 	  	echo "add $a.$b.$c.1/24 10.1.0.10 2"
		done
		echo "EOF"
	done
done
) | nc localhost 12345
