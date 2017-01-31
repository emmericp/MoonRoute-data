local dpdk		= require "dpdk"
local memory	= require "memory"
local lpm     = require "lpm"
local bitmask = require "bitmask"
local profile = require("jit.profile")

local profile_stats = {}

local mod = {}

function profile_callback(thread, samples, vmstate)
  local dump = profile.dumpstack(thread, "l (f) << ", 1)
  --printf("profile cb: " .. dump)
  if(profile_stats[dump]) then
    profile_stats[dump] = profile_stats[dump] + 1
  else
    profile_stats[dump] = 1
  end
end

--- Starts a fast path instance
-- @param initLpmTable LPM table which should be used afer initialization
-- @param distributor Distributor to use
-- @param rxQueues a lis of rxQueues, which should be handled by this fastPath
-- @param slowQueue a fastPipe which will be used to transmit packets to the
--  slowPath
-- @param cmdRxQueue a slowPipe, on which the fastPath is receiving configuration
--  commands
-- @param cmdTxQueue a slowPipe, on which the Fast path is transmitting
--  configuration and status messages
-- @param maxBurstSize maximum number of packets, which are processed in each
--  fastPath iteration
function mod.run(initLpmTable, distributor, rxQueues, slowQueue, cmdRxQueue, cmdTxQueue, maxBurstSize, coreId, testTxQueue)
  local lpmTable = initLpmTable
  --print("slave here")

  -- Allocate mbufs for packets...:
  --local mem = memory.createMemPool({n=4095})
  local mem = memory.createMemPool({n=256})
  local bufs = mem:bufArray(maxBurstSize)

  -- Create a bitmask (specifies, for which packets we want to do the lookup):
  local in_mask = bitmask.createBitMask(maxBurstSize)

  -- Create an other Bitmask, to see for which packets a route could be found:
  local out_mask = bitmask.createBitMask(maxBurstSize)
  local valid_mask = bitmask.createBitMask(maxBurstSize)

  -- Allocate Entry pointers, which will point to the routing table entries
  -- for all routed packets:
  local entries = lpmTable:allocateEntryPtrs(maxBurstSize)

  local nrx
  --profile.start("l", profile_callback)

  printf("core %d started running!!!", coreId)
  for _, queue in ipairs(rxQueues) do
    printf("core %d reading from dev %d queue %d", coreId, queue.id, queue.qid)
  end
  --if(coreId ~= 3) then
  --  printf("core %d quit", coreId)
  --  return
  --end
  --local totRx = 0
  while dpdk.running() do
    local nrxmax = 0
    -- RR Arbiter over all configured rxQueues:
    for i, rxQueue in ipairs(rxQueues) do
      -- try to receive a maximum of maxBurstSize of packets/mbufs:
      --print("try rx...")
      nrx = rxQueue:tryRecv(bufs, 0)
      if (nrx > 0) then
        --totRx = totRx + nrx
        --print("core " .. tostring(coreId) .. "rxed on queue " .. tostring(rxQueue.qid) .. " n.pkts: " .. tostring(nrx) .. " total: " .. tostring(totRx))
        -- prepare in_mask for the received packets
        in_mask:clearAll()
        out_mask:clearAll()
        valid_mask:clearAll()
        in_mask:setN(nrx)

        -- IP checksum should be calculated in hardware
        bufs:offloadIPChecksums(nil, nil, nil, nrx)
        -- print("chksum off")

        --printf("---")
        --printf("in:")
        --in_mask:printout()
        --printf("in:")
        --in_mask:printoutcompact()
        bufs:checkValidIPv4C(in_mask, valid_mask)
        --printf("valid:")
        --out_mask:printoutcompact()
        --printf("out:")
        --out_mask:printout()
        --print("validated")

        -- Decrement TTL, and detect packets with TTL <=1
        lpm.decrementTTL_pipeC(bufs, valid_mask, out_mask, slowQueue)
        --printf("ttl:")
        --out_mask:printoutcompact()
        --lpm.decrementTTLC(bufs, out_mask, out_mask)
        --bitmask.bnot(out_mask, fail_mask)
        --bitmask.band(in_mask, fail_mask, fail_mask)
        -- this causes a lot of performance overhead
        --slowQueue:enqueueMbufsMask(bufs, fail_mask)
        
        -- TODO: the right place would be in memory.lua
        --  but masks might confuse

        -- Do the lookup for the whole burst:
        lpmTable:lookupBurst_pipe(bufs, out_mask, out_mask, slowQueue, entries)
        --printf("lookup:")
        --out_mask:printoutcompact()
        --print("afte rlookup")
        --lpmTable:lookupBurst(bufs, in_mask, out_mask, entries)

        -- Apply the routes
        -- (write destination mac address to packets)
        lpm.applyRoute(bufs, out_mask, entries, nil)
        --if(out_mask[1]) then
        --  printf("nh if = %d", entries[1].interface)
        --  printf("nh mac = %s", entries[1].mac_next_hop:getString())
        --end
        --entries[1].interface = 0
        --printf("nh if = %d", entries[1].interface)
        --print("route applied")


        -- Send packets to their designated interfaces
        -- (distributor also writes correct src mac addr to packets)
        --printf("core %d out_mask: ", coreId)
        --out_mask:printoutcompact()
        distributor:send(bufs, out_mask, entries)
        -- testTxQueue:sendN(bufs, nrx)

        --print("sent")

        -- Free all packets, which we could not send
        --out_mask:printout()
        bitmask.bnot(valid_mask, valid_mask)
        bitmask.band(valid_mask, in_mask, valid_mask)
        -- now the valid mask is an "invalid" mask
        --out_mask:printout()
        --printf("core %d validmask: ", coreId)
        --valid_mask:printoutcompact()
        --bufs:freeMask(valid_mask)
        bufs:freeMaskC(valid_mask)
        --print("free")

        -- nrxmax is used to estimate the workload of this core
        if (nrx > nrxmax) then
          nrxmax = nrx
        end
        --bufs:free(128)
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

    -- handle the command interface:
    local cmd = cmdRxQueue:tryRecv(0)
    if(cmd) then
      -- we have a cmd pending, so we process it
      if(cmd.command == "NewTable") then
        print "FP: new table received"
        -- switch to the new table
        lpmTable = cmd.lpmTable
        -- we processed the command, so send an ACK
        local ack = {command = "ACK", sequenceNr = cmd.sequenceNr}
        cmdTxQueue:send(ack)
      else
        -- we do not recognize the command
        -- so we send a NACK
        local nack = {command = "NACK", sequenceNr = cmd.sequenceNr}
        cmdTxQueue:send(nack)
      end
    end
  end
  --print("core " .. tostring(coreId) .. " total: " .. tostring(totRx))

  --profile.stop()

  --print("Profiler results:")

  --for i,v in pairs(profile_stats) do
  --  print( v .. " ::: " .. i)
  --end
end

return mod
