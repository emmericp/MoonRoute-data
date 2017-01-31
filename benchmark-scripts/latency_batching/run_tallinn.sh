#!/bin/bash

cd /root/MoonGen/build

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["tallinn", "palanga"], "start$i": ["tallinn", "palanga"] }' 

maxa=11                                                                         
maxi=2                                                                          
maxj=1                                                                          
                                                                                
#FIXME: rates                                                                   
for a in $(seq 1 $maxa) ; do  # input batching                                  
  for i in 8 128 ; do # output batching                                       
    for j in $(seq 1 $maxj) ; do           
      cat ~/cfg_part1.lua > ~/cfg.lua
      inputb=$((2**($a-1)))
      outputb=$i
      echo "config[\"txQueueSize\"] = ${outputb}" >> ~/cfg.lua
      echo "config[\"rxBurstSize\"] = ${inputb}" >> ~/cfg.lua
      cat ~/cfg_part2.lua >> ~/cfg.lua
      echo "starting: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${i}"
      echo "sync on  start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
      /root/MoonGen/build/MoonGen ~/router.lua 8&
      sleep 70
      killall MoonGen
      echo "finished: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${i}"
      echo "sync on  end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
    done
  done
done
