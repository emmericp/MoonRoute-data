local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local ip4 = require "proto.ip4"
local ts = require "timestamping"
local hist = require "histogram"
local timer = require "timer"
local ns = require "namespaces"
require "utils"

local global = ns:get()

function master(dev, filename, prefix, width)
  setRandomSeed(97629)
  dev = device.config{port=dev, txQueues = 4, rxQueues = 2}
  device.waitForLinks()
  dpdk.launchLua("counterSlave", {dev},  prefix,  filename, {dev:getTxQueue(0), dev:getTxQueue(2), dev:getTxQueue(3)})
  dpdk.launchLua("loadSlave", dev, dev:getTxQueue(0), width)
  dpdk.launchLua("loadSlave", dev, dev:getTxQueue(2), width, true)
  dpdk.launchLua("loadSlave", dev, dev:getTxQueue(3), width, true)
  dpdk.launchLua("timerSlave", dev:getTxQueue(1), dev:getRxQueue(1), width, prefix, filename)
  dpdk.waitForSlaves()
end

function timerSlave(txQueue, rxQueue, width, prefix, filename)
	rxQueue.dev:filterTimestamps(rxQueue)
	local timestamper = ts:newUdpTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	dpdk.sleepMillis(5000) -- ensure that the load task is running and load was determined
	local counter = 0
	local rateLimit = timer:new(0.001)
	while dpdk.running() do
		hist:update(timestamper:measureLatency(84, function(buf)
			buf:getUdpPacket():fill{
				pktLength = 84,
				ethSrc = rxQueue,
				ethDst = "a0:36:9f:3b:6d:50",
				ip4Dst = "10.0.0.13",
      				ip4Dst = math.random() * 2^width,
				ip4TTL = 60,
				udpSrc = 1234,
				udpDst = 5678,	
			}
		end))
		rateLimit:wait()
		rateLimit:reset()
	end
	-- print the latency stats after all the other stuff
	dpdk.sleepMillis(300)
	hist:print()
	local histName = filename .."/" .. prefix ..  "-hist.csv"
	hist:save(histName)
end

function counterSlave(devices, prefix, filename, txQueues)
  print("counter slave running")
  local file = io.open(filename, "a")
  dpdk.sleepMillisIdle(2000)
assert(#devices == 1, "only 1 dev supported for TS at the moment, sorry")
	local counters = {}
	for i, dev in ipairs(devices) do
		counters[i] = stats:newDevRxCounter(prefix .. dev:getMacString(), dev, "plain", file)
	end
	for _, ctr in ipairs(counters) do
		ctr:update()
	end
  dpdk.sleepMillisIdle(1000)
	-- while dpdk.running() do
	-- 	for _, ctr in ipairs(counters) do
	-- 		ctr:update()
	-- 	end
	-- 	dpdk.sleepMillisIdle(10)
	-- end
	local tp
	for _, ctr in ipairs(counters) do
		ctr:update()
		local mpps, mbit = ctr:getStats()
		print(unpack(mbit))
		print(unpack(mpps))
		tp = mbit[1]
	end
	print("throughput: " .. tp)
	for i, q in ipairs(txQueues) do
		q:setRate(tp * 0.9 / #txQueues)
	end
  dpdk.sleepMillis(54000)
  dpdk.stop()
end


function loadSlave(dev, queue, width, noStats)
  print("Load slave running... width = " .. tostring(width))
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = 60,
			ethSrc = queue,
			ethDst = "a0:36:9f:3b:6d:50",
			ip4Dst = "10.0.0.13",
			--ip4Dst = ip4.getRandomAddress().uint32,
			ip4TTL = 60,
			udpSrc = 1234,
			udpDst = 5678,	
		}
	end)
	bufs = mem:bufArray(128)
	local baseIP = parseIPAddress("10.0.0.1")
	local flow = 0
	local ctr = stats:newDevTxCounter(dev, "plain")
	while dpdk.running() do
		bufs:alloc(60)
		for _, buf in ipairs(bufs) do
		  local pkt = buf:getIP4Packet()
      pkt.ip4.dst:set(0 + math.random() * 2^width)
    end
		--for _, buf in ipairs(bufs) do
		--	local pkt = buf:getUdpPacket()
		--	pkt.ip4.src:set(baseIP + flow)
		--	flow = incAndWrap(flow, numFlows)
		--end
		-- UDP checksums are optional, so just IP checksums are sufficient here
		bufs:offloadIPChecksums()
		queue:send(bufs)
		if not noStats then
		ctr:update()
	end
	end
	ctr:finalize()
end
