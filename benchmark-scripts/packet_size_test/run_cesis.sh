#!/bin/bash

cd /root/MoonGen/build

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["cesis", "nida"], "start$i": ["cesis", "nida"] }' 

maxa=1
maxi=16
maxj=2

for a in $(seq 1 $maxa) ; do  # input batching
  for i in $(seq 1 $maxi) ; do # output batching
    for j in $(seq 1 $maxj) ; do
      #cp ~/cfgs/cfg${i}.lua ~/cfg.lua
      echo "sync on  start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
      echo "starting router run $i $j"
      /root/MoonGen/build/MoonGen ~/router.lua 1 &
      sleep 30
      killall MoonGen
      echo "sync on  end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
    done
  done
done
