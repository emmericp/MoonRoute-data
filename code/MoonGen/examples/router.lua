local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local lpm     = require "lpm"
local serpent = require "Serpent"
local ffi     = require "ffi"
local bitmask = require "bitmask"
local filters = require "filter"
local lshift = bit.lshift
local distribute = require "distribute"
local arp = require "proto.arp"
local ip = require "proto.ip4"
local profile = require("jit.profile")
local pipe = require "pipe"

ffi.cdef [[
struct table_entry {
  uint32_t ip_next_hop;
  uint8_t interface;
  struct mac_address mac_next_hop;
};
]]

function master(txPort, ...)

  local dev = device.get("A0:36:9F:3B:6D:52")
  if(dev) then
    printf("found device: %d", dev.id)
  else
    printf("no device found")
  end
  -- configure the device (setup queues + RSS)
  --local txDev = device.config({port=txPort, rxQueues=4+4, txQueues=4, rssNQueues=4})
  printf("configure device ...")
  local txDev = device.config({port=txPort, rxQueues=4+4, txQueues=5})
  dpdk.enablePowerManagement(2)
  dpdk.setCPUFreqMin(2)
  printf(" done")
  printf("waiting for links ...")
  device.waitForLinks()
  printf(" done")

  -- XXX this is the actual queue ID starting with 0 as the first queue
  -- TODO: update this in moongen documentation
  local arpRxQueue = txDev:getRxQueue(5)
  local arpTxQueue = txDev:getTxQueue(3)
  --dpdk.launchLuaOnCore(9, arp.arpTask, {rxQueue = arpRxQueue, txQueue = arpTxQueue, ips = {"10.0.0.130", "10.0.0.10", "10.0.0.11", "10.0.0.12", "10.0.0.13", "10.0.0.129"}})
  dpdk.launchLuaOnCore(1, arp.arpTask, {rxQueue = arpRxQueue, txQueue = arpTxQueue, ips = {"10.0.0.130", "10.0.0.10", "10.0.0.11", "10.0.0.12", "10.0.0.13", "10.0.0.129"}})
  print("ARP slave running")

  -- Create a new routing table.
  -- The Table entry is given as our user specified C datatype:
  local lpmTable = lpm.createLpm4Table(nil, nil, "struct table_entry")

  -- We add some entries to our routing table:
  local entry = lpmTable:allocateEntry()
  entry.ip_next_hop = parseIPAddress("10.0.0.0")
  entry.interface = 0
  entry.mac_next_hop = parseMacAddress("A0:36:9F:59:07:00")

  lpmTable:addEntry(parseIPAddress("10.0.0.0"), 25, entry)

  -- We can reuse the same entry...
  entry.ip_next_hop = parseIPAddress("10.0.0.1")
  entry.interface = 1
  entry.mac_next_hop = parseMacAddress("A0:36:9F:59:07:00")

  lpmTable:addEntry(parseIPAddress("10.0.0.128"), 25, entry)

  entry.ip_next_hop = parseIPAddress("10.0.0.1")
  entry.interface = 2
  entry.mac_next_hop = parseMacAddress("A0:36:9F:59:07:00")

  -- more specific route to 10.0.0.130
  lpmTable:addEntry(parseIPAddress("10.0.0.130"), 32, entry)


  -- we create a distributor, which will distribute packets to output
  -- queues according to the result of the routing algorithm
  -- (This is basically an output redirection table)
  local distributor = distribute.createDistributor(nil, 4, 4, false)
  -- register outputs
  distributor:registerOutput(0, txDev:getTxQueue(0), 128, 1)
  distributor:registerOutput(1, txDev:getTxQueue(1), 128, 5)
  distributor:registerOutput(2, txDev:getTxQueue(2), 128, 2)

  -- create a 5tuple filter, which matches packets with destination ipv4
  -- addr of 10.0.0.10
  txDev:addHW5tupleFilter({dst_ip = parseIPAddress("10.0.0.10"), l4protocol = 0}, txDev:getRxQueue(4))

  local slowQueue = pipe.newFastCPipe()

  -- Run the actual routing core:
  --dpdk.launchLuaOnCore(8, "slave", lpmTable, distributor, {txDev:getRxQueue(0), txDev:getRxQueue(1), txDev:getRxQueue(2), txDev:getRxQueue(3), txDev:getRxQueue(4)}, 128)
  dpdk.launchLuaOnCore(2, "slave", lpmTable, distributor, {txDev:getRxQueue(0), txDev:getRxQueue(1), txDev:getRxQueue(2), txDev:getRxQueue(3), txDev:getRxQueue(4)}, 128, slowQueue)




  -- Now we set up the slow path:
  local distributor_slow = distribute.createDistributor(nil, 4, 4, false)
  -- register outputs
  distributor_slow:registerOutput(0, txDev:getTxQueue(4), 128, 1)
  distributor_slow:registerOutput(1, txDev:getTxQueue(4), 128, 5)
  distributor_slow:registerOutput(2, txDev:getTxQueue(4), 128, 2)

  local entry = lpmTable:allocateEntryPtrs(1)
  while dpdk.running() do
    local pkt = slowQueue:dequeueMbuf()
    if pkt then
      --printf("slow path rxed")
      -- FIXME: why is the router not crashing, when i do not free here??????
      local ttl = pkt:getIPPacket().ip4:getTTL()
      --pkt:free();
      --printf("ttl = %u, len %u", ttl, pkt.pkt.data_len)
      if(lpm.decrementTTL_single(pkt)) then
        --printf(" dui")
        if(lpmTable:lookup_single(pkt, entry)) then
          --printf(" snd")
          lpm.applyRoute_single(pkt, entry, 5)
          --printf(" snd2")
          -- XXX in the current test we should not reach this code, however we do... why?
          -- XXX we are segfaulting somewhere here in send_single...
          distributor_slow:send_single(pkt, entry)
          pkt:free()
        else
          printf("AAHH free")
          pkt:free()
        end
      else
        printf("AAHH free")
        pkt:free()
      end
    end
  end
  dpdk.waitForSlaves()
  collectgarbage("collect")
end

local profile_stats = {}

function profile_callback(thread, samples, vmstate)
  local dump = profile.dumpstack(thread, "l (f) << ", 1)
  --printf("profile cb: " .. dump)
  if(profile_stats[dump]) then
    profile_stats[dump] = profile_stats[dump] + 1
  else
    profile_stats[dump] = 1
  end
end

--function slave(lpmTable_table, txDev, rxDev)
function slave(lpmTable, distributor, rxQueues, maxBurstSize, slowQueue)
  --print("slave here")

  -- Allocate mbufs for packets...:
  local mem = memory.createMemPool({n=4095})
  local bufs = mem:bufArray(maxBurstSize)

  -- Create a bitmask (specifies, for which packets we want to do the lookup):
  local in_mask = bitmask.createBitMask(maxBurstSize)

  -- Create an other Bitmask, to see for which packets a route could be found:
  local out_mask = bitmask.createBitMask(maxBurstSize)
  local fail_mask = bitmask.createBitMask(maxBurstSize)

  -- Allocate Entry pointers, which will point to the routing table entries
  -- for all routed packets:
  local entries = lpmTable:allocateEntryPtrs(maxBurstSize)

  local nrx
  profile.start("l", profile_callback)

  while dpdk.running() do
    local nrxmax = 0
    -- RR Arbiter over all configured rxQueues:
    for i, rxQueue in ipairs(rxQueues) do
      -- try to receive a maximum of maxBurstSize of packets/mbufs:
      --print("try rx...")
      nrx = rxQueue:tryRecv(bufs, 0)
      if (nrx > 0) then
        --print("rxed on queue " .. tostring(rxQueue.qid) .. " n.pkts: " .. tostring(nrx))
        -- prepare in_mask for the received packets
        in_mask:clearAll()
        out_mask:clearAll()
        fail_mask:clearAll()
        in_mask:setN(nrx)

        -- IP checksum should be calculated in hardware
        bufs:offloadIPChecksums(nil, nil, nil, nrx)
        -- print("chksum off")

        --printf("---")
        --printf("in:")
        --in_mask:printout()
        bufs:checkValidIPv4C(in_mask, out_mask)
        --printf("out:")
        --out_mask:printout()
        --print("validated")

        -- Decrement TTL, and detect packets with TTL <=1
        lpm.decrementTTL_pipeC(bufs, out_mask, out_mask, slowQueue)
        --lpm.decrementTTLC(bufs, out_mask, out_mask)
        --bitmask.bnot(out_mask, fail_mask)
        --bitmask.band(in_mask, fail_mask, fail_mask)
        -- this causes a lot of performance overhead
        --slowQueue:enqueueMbufsMask(bufs, fail_mask)
        
        -- TODO: the right place would be in memory.lua
        --  but masks might confuse
        
        -- ---
        -- Branch to slow path for ICMP will come here...
        -- ---

        -- Do the lookup for the whole burst:
        lpmTable:lookupBurst_pipe(bufs, out_mask, out_mask, slowQueue, entries)
        --print("afte rlookup")
        --lpmTable:lookupBurst(bufs, in_mask, out_mask, entries)

        -- Apply the routes
        -- (write destination mac address to packets)
        lpm.applyRoute(bufs, out_mask, entries, 5)
        --print("route applied")


        -- Send packets to their designated interfaces
        -- (distributor also writes correct src mac addr to packets)
        distributor:send(bufs, out_mask, entries)
        --print("sent")

        -- Free all packets, which we could not send
        --print("--2:")
        --out_mask:printout()
        bitmask.bnot(out_mask, out_mask)
        bitmask.band(out_mask, in_mask, out_mask)
        --print("--3:")
        --out_mask:printout()
        --bufs:freeMask(out_mask)
        bufs:freeMaskC(out_mask)
        --print("free")

        -- nrxmax is used to estimate the workload of this core
        if (nrx > nrxmax) then
          nrxmax = nrx
        end
        --print "done"
      --else
      --  printf("not received")
      end
    end
    
    -- handle timeouts
    -- This is an implementation of daniel's idea of only flushing, when we have nothing to do.
    -- We assume, if we only received small bursts, the router has not much to do
    -- Under full load, flows, with little traffic will starve :(
    if(nrxmax < maxBurstSize/2) then
      --printf("update timer: nrxmax = %d", nrxmax)
      --bufs:adsfasd()
      distributor:handleTimeouts()
    end
  end

  profile.stop()

  print("Profiler results:")

  for i,v in pairs(profile_stats) do
    print( v .. " ::: " .. i)
  end

  -- this is just for testing garbage collection
  collectgarbage("collect")
end
