#!/bin/bash

cd /root/MoonGen/build

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["cesis", "nida"], "start$i": ["cesis", "nida"] }' 

for i in $(seq 1 7) ; do
  for j in $(seq 1 4) ; do
    cp ~/cfgs/cfg${i}.lua ~/cfg.lua
    echo "syncing on  start$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync start$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
    echo "starting router run $i $j"
    /root/MoonGen/build/MoonGen ~/router.lua 1 &
    sleep 30
    killall MoonGen
    echo "syncing on  end$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync end$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
  done
done
