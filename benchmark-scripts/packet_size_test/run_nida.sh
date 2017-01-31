#!/bin/bash

cd /root/MoonGen/build

mkdir ~/results

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["cesis", "nida"], "start$i": ["cesis", "nida"] }' 

maxa=1
maxi=16
maxj=2

for a in $(seq 1 $maxa) ; do  # input batching
  for i in $(seq 1 $maxi) ; do # output batching
    for j in $(seq 1 $maxj) ; do
      echo "sync on  start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
      #if [ "$j" -gt 5 ]; then
      sleep 10
      #fi
      pktSize=$(( 64+($i-1)*32 ))
      /root/MoonGen/build/MoonGen ~/counter.lua 0 3 ~/results/run pktSize_${pktSize}_run_${j}_ $pktSize
      echo "sync on  end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
    done
  done
done
