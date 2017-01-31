#!/bin/bash

cd /root/MoonGen/build

testbed-rapidsync-reset
testbed-rapidsync-set '{ "end$i": ["narva", "klaipeda"], "start$i": ["narva", "klaipeda"] }'

w=24
for i in $(seq 1 9) ; do
  for j in $(seq 1 4) ; do
    #cp ~/cfgs/cfg${i}.lua ~/cfg.lua
    echo "syncing on  start$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync start$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
    /root/MoonGen/build/MoonGen ~/router.lua 12&
    sleep 30
    /root/pmu-tools-master/ocperf.py stat -C 1 -x , -e mem_load_uops_retired.llc_miss,mem_load_uops_retired.l2_miss,mem_load_uops_retired.l1_miss,branch-misses sleep 1 2>&1 | /root/miss_extract.pl "[cfg_${w}_run_${j}_" >> /root/results/cacherun
    sleep 5
    killall MoonGen
    echo "syncing on  end$(( ($i-1) * 10 + ($j-1)))"
    testbed-sync end$(( ($i-1) * 10 + ($j-1)))
    echo " OK"
  done
  w=$((w + 1))
done
