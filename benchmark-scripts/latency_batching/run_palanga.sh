#!/bin/bash

cd /root/MoonGen/build

mkdir ~/results

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["tallinn", "palanga"], "start$i": ["tallinn", "palanga"] }' 

w=24

maxa=11
maxi=2
maxj=1

for a in $(seq 1 $maxa) ; do  # input batching
  for i in 8 128 ; do # output batching
    for j in $(seq 1 $maxj) ; do
      inputb=$(( 2**($a-1) ))
      outputb=$i
      echo "starting: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${j}"
      echo "sync on  start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync start$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
      #if [ "$j" -gt 5 ]; then
      sleep 10
      #fi
      /root/MoonGen/build/MoonGen ~/load.lua 0 ~/results/run input_${inputb}_output_${outputb}_run_${j}_ 32
      echo "finished: inputBatch = ${inputb}   outputBatch = ${outputb}  a=$a  i=$i j=${i}"
      echo "sync on  end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))"
      testbed-sync end$(( ($a-1) * $maxi * $maxj + ($i-1) * $maxj + ($j-1)))
      echo " OK"
    done
  done
done
