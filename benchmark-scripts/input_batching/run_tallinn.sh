#!/bin/bash

cd /root/MoonGen/build

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["tallinn", "palanga"], "start$i": ["tallinn", "palanga"] }' 

maxa=1
maxi=9
maxj=2

for a in $(seq 1 $maxa) ; do  # input batching
  for i in $(seq 1 $maxi) ; do # output batching
    for j in $(seq 1 $maxj) ; do
      cat ~/cfg_part1.lua > ~/cfg.lua
      inputb=$((2**($a-1)))
      outputb=$(( 2**$i ))
      echo "config[\"txQueueSize\"] = ${outputb}" >> ~/cfg.lua
      echo "config[\"rxBurstSize\"] = ${inputb}" >> ~/cfg.lua
      cat ~/cfg_part2.lua >> ~/cfg.lua
      echo "starting: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${i}"
      echo "sync on  start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
      /root/MoonGen/build/MoonGen ~/router.lua 8&
      sleep 30
      killall MoonGen
      echo "finished: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${i}"
      echo "sync on  end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
    done
  done
done
