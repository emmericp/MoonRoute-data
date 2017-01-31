#!/bin/bash

cd /root/MoonGen/build

mkdir ~/results

testbed-rapidsync-reset
#testbed-rapidsync-set '{ "end$i": ["tallinn", "palanga"], "start$i": ["tallinn", "palanga"] }' 
testbed-rapidsync-set '{ "end$i": ["narva", "klaipeda"], "start$i": ["narva", "klaipeda"] }' 

w=24

maxa=11
maxi=7
maxj=4

for a in $(seq 11 $maxa) ; do  # input batching
  for i in $(seq 7 $maxi) ; do # output batching
    for j in $(seq 1 $maxj) ; do
      inputb=$(( 2**($a-1) ))
      outputb=$(( 2**$i ))
      echo "starting: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${i}"
      echo "sync on  start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
      #if [ "$j" -gt 5 ]; then
      sleep 15
      #fi
      /root/MoonGen/build/MoonGen ~/load_cache.lua 1 ~/results/run input_${inputb}_output_${outputb}_run_${j}_ 32
      echo "finished: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${i}"
      echo "sync on  end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
    done
  done
done
