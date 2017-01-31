#!/bin/bash

cd /root/MoonGen/build

mkdir ~/results

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["cesis", "nida"], "start$i": ["cesis", "nida"] }' 

for i in $(seq 1 7) ; do
  for j in $(seq 1 4) ; do
    echo "syncing on  start$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync start$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
    #if [ "$j" -gt 5 ]; then
    sleep 7
    #fi
    /root/MoonGen/build/MoonGen ~/counter.lua 0 3 ~/results/run cfg_${i}_run_${j}_
    echo "finished run $i $j"
    echo "syncing on  end$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync end$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
  done
done
