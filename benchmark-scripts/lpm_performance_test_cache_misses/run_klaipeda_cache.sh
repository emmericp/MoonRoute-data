#!/bin/bash

cd /root/MoonGen/build

mkdir ~/results

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["narva", "klaipeda"], "start$i": ["narva", "klaipeda"] }'

w=24

for i in $(seq 1 9) ; do
  for j in $(seq 1 4) ; do
    echo "syncing on  start$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync start$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
    #if [ "$j" -gt 5 ]; then
    sleep 15
    #fi
    /root/MoonGen/build/MoonGen ~/load.lua 1 ~/results/run cfg_${w}_run_${j}_ $w
    echo "finished run $i $j"
    echo "syncing on  end$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync end$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
  done
  w=$((w + 1))
done
