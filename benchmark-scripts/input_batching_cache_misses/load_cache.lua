local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local ip4 = require "proto.ip4"
require "utils"

function master(dev, filename, prefix, width)
  setRandomSeed(97629)
  dev = device.config{port=dev}
	device.waitForLinks()
	dpdk.launchLua("counterSlave", {dev},  prefix,  filename)
  dpdk.launchLua("loadSlave", dev, dev:getTxQueue(0), width)
	dpdk.waitForSlaves()
end

function counterSlave(devices, prefix, filename)
  print("counter slave running")
  local file = io.open(filename, "a")
  dpdk.sleepMillisIdle(2000)

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
	for _, ctr in ipairs(counters) do
		ctr:update()
	end
  dpdk.sleepMillisIdle(20000)
  dpdk.stop()
end


function loadSlave(dev, queue, width)
  print("Load slave running... width = " .. tostring(width))
	local mem = memory.createMemPool(function(buf)
		buf:getUdpPacket():fill{
			pktLength = 60,
			ethSrc = queue,
			ethDst = "90:e2:ba:2c:cb:02",
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
		ctr:update()
	end
	ctr:finalize()
end
