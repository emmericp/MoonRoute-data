local dpdk		= require "dpdk"
local memory	= require "memory"
local device	= require "device"
local stats		= require "stats"
local ip4 = require "proto.ip4"
require "utils"

function master(dev1, dev2)
  setRandomSeed(97629)
  dev1 = device.config{port=dev1}
  dev2 = device.config{port=dev2}
	device.waitForLinks()
	dpdk.launchLuaOnCore(9, "counterSlave", {dev1, dev2})
  dpdk.launchLuaOnCore(10, "loadSlave1", dev1, dev1:getTxQueue(0))
  dpdk.launchLuaOnCore(11, "loadSlave2", dev2, dev2:getTxQueue(0))
	dpdk.waitForSlaves()
end

function counterSlave(devices)
  print("counter slave running")
  --local file = io.open("testfile", "w")
  --dpdk.sleepMillisIdle(5000)
	local counters = {}
	for i, dev in ipairs(devices) do
		--counters[i] = stats:newDevRxCounter(dev:getMacString(),dev, "plain", file)
		counters[i] = stats:newDevRxCounter(dev:getMacString(),dev, "plain")
	end
  --for _, ctr in ipairs(counters) do
  --  ctr:update()
  --end
  --dpdk.sleepMillisIdle(5000)
  --for _, ctr in ipairs(counters) do
  --  ctr:update()
  --end
  --dpdk.stop()
	while dpdk.running() do
		for _, ctr in ipairs(counters) do
			ctr:update()
		end
		dpdk.sleepMillisIdle(10)
	end
	for _, ctr in ipairs(counters) do
		ctr:update()
	end
end


function loadSlave1(dev, queue)
  print("Load slave running")
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
  local dst = parseIPAddress("87.0.0.4")
	while dpdk.running() do
		bufs:alloc(60)
		for _, buf in ipairs(bufs) do
		  local pkt = buf:getIP4Packet()
      pkt.ip4.dst:set(math.random() * 63)
      --pkt.ip4.dst:set(dst)
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
function loadSlave2(dev, queue)
  print("Load slave running")
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
  local dst = parseIPAddress("200.0.0.4")
	while dpdk.running() do
		bufs:alloc(60)
		for _, buf in ipairs(bufs) do
		  local pkt = buf:getIP4Packet()
      pkt.ip4.dst:set(2^31 + math.random() * 63)
      --pkt.ip4.dst:set(dst)
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
