#!/bin/bash

cd /root/MoonGen/build

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["tallinn", "palanga"], "start$i": ["tallinn", "palanga"] }' 

for i in $(seq 1 9) ; do
  for j in $(seq 1 4) ; do
    #cp ~/cfgs/cfg${i}.lua ~/cfg.lua
    echo "syncing on  start$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync start$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
    /root/MoonGen/build/MoonGen ~/router.lua &
    sleep 30
    killall MoonGen
    echo "syncing on  end$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync end$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
  done
done
