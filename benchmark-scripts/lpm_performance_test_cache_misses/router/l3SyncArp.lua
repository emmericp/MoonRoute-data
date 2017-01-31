require "headers"
local arp = require "proto.arp"
local ffi = require "ffi"
local pkt = require "packet"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local memory = require "memory"
local filter = require "filter"

local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift

local eth = require "proto.ethernet"

local router_syncArp = {}
mod.router_syncArp = router_syncArp
router_syncArp.__index = router_syncArp

--pkt.getArpPacket = packetCreate("eth", "arp")

function mod.createSyncArp(config, arpRxQueueNum, arpTxQueueNum)
  local ipToMac = {}
  for _, port in pairs(config.ports) do
    port.arpRxQueue = port.arpRxQueue or port.device:getRxQueue(arpRxQueueNum)
    port.arpTxQueue = port.arpTxQueue or port.device:getTxQueue(arpTxQueueNum)
    ipToMac[parseIPAddress(port.ipv4)] = port.arpTxQueue.dev:getMac()
    port.arpRxQueue.dev:l2Filter(eth.TYPE_ARP, port.arpRxQueue)
  end

  local rxBufs = memory.createBufArray(1)
	local txMem = memory.createMemPool(function(buf)
		buf:getArpPacket():fill{ 
			arpOperation	= arp.OP_REPLY,
			pktLength		= 60
		}
	end)
	local txBufs = txMem:bufArray(1)

  return setmetatable({
    config = config,
    arpTable = {},
    ipToMac = ipToMac,
    rxBufs = rxBufs,
    txMem = txMem,
    txBufs = txBufs
  }, router_syncArp)
end

function router_syncArp:handle()
  -- handle incoming ARP packets
  for portname, port in pairs(self.config.ports) do
      -- printf("try recv ARP on %s queuenr %d", portname, port.arpRxQueue.qid)
			local rx = port.arpRxQueue:tryRecv(self.rxBufs, 0)
      --printf("rx num = %d", rx)
			assert(rx <= 1)
			if rx > 0 then
        --printf(" -> rxed ARP")
        local free_packet = true
				local rxPkt = self.rxBufs[1]:getArpPacket()
				if rxPkt.eth:getType() == eth.TYPE_ARP then
					if rxPkt.arp:getOperation() == arp.OP_REQUEST then
						local ip = rxPkt.arp:getProtoDst()
						local mac = self.ipToMac[ip]
						if mac then
							self.txBufs:alloc(60)
							local pkt = self.txBufs[1]:getArpPacket()
							pkt.eth:setSrc(mac)
							pkt.eth:setDst(rxPkt.eth:getSrc())
							pkt.arp:setOperation(arp.OP_REPLY)
							pkt.arp:setHardwareDst(rxPkt.arp:getHardwareSrc())
							pkt.arp:setHardwareSrc(mac)
							pkt.arp:setProtoDst(rxPkt.arp:getProtoSrc())
							pkt.arp:setProtoSrc(ip)
							port.arpTxQueue:send(self.txBufs)
						end
					elseif rxPkt.arp:getOperation() == arp.OP_REPLY then
						-- learn from all arp replies we see (arp cache poisoning doesn't matter here)
            -- TODO: this will eventually overflow memory, as arpTable entries never get removed
            --  -> we have to implement something like a replacement strategy (LRU or oldest first)
						local mac = rxPkt.arp:getHardwareSrcString()
						local ip = rxPkt.arp:getProtoSrcString()
						self.arpTable[tostring(parseIPAddress(ip))] = { mac = mac, timestamp = dpdk.getTime() }
            -- we also forward the whole arp packet upstream if possible (to linux kernel)
            -- TODO: maybe give this as a function to the ARP module at init
            if(port.virtualDev) then
              free_packet = false
              port.virtualDev:txSingle(pkt)
            end
					end
				end
        if(free_packet) then
          self.rxBufs:freeAll()
        end
			end
		end

		-- send outstanding requests 
    for ip, value in pairs(self.arpTable) do
			-- TODO: refresh or GC old entries
      -- FIXME: arpTable entries never get old :( so we can not react to changing network topology
			if value ~= "pending" then
				return
			end
			self.arpTable[ip] = "requested"
			-- TODO: the format should be compatible with parseIPAddress
			ip = tonumber(ip)
      --printf("ip x = %x", ip);
			self.txBufs:alloc(60)
			local pkt = self.txBufs[1]:getArpPacket()
			pkt.eth:setDstString(eth.BROADCAST)
			pkt.arp:setOperation(arp.OP_REQUEST)
			pkt.arp:setHardwareDstString(eth.BROADCAST)
			pkt.arp:setProtoDst(ip)
      -- We now try to find the network interface, which is in the right subnet:
      local packet_dst_ip = ip
      for portname, port in pairs(config.ports) do
        local port_ip = parseIPAddress(port.ipv4)
      --printf("portip x = %x", port_ip);
        local netmask = rshift(0x80000000,port.ipv4Prefix - 1) - 1
        netmask = util_bnot32(netmask)
        netmask = util_band32(netmask,   0xffffffff)
        local a = util_band32(packet_dst_ip, netmask)
        local b = util_band32(port_ip, netmask)
        if(a == b) then
      ---- FIXME: smoethimes we do not match here
        --if(util_band32(packet_dst_ip, netmask) == util_band32(port_ip, netmask)) then
          --printf("found and sent")
          local mac = port.arpTxQueue.dev:getMac()
          pkt.eth:setSrc(mac)
          pkt.arp:setProtoSrc(parseIPAddress(port.ipv4))
          pkt.arp:setHardwareSrc(mac)
          port.arpTxQueue:send(self.txBufs)
          break
        end
        --printf("no dev found")
        --printf("a = %x, b =%x", a, b);
      end
		end
    -- FIXME: why is this delay here???
		--dpdk.sleepMillisIdle(1)
end


--- Lookup the MAC address for a given IP.
-- Blocks for up to 1 second if the arp task is not yet running
-- Caution: this function uses locks and namespaces, must not be used in the fast path
function router_syncArp:lookup(ip)
	if type(ip) == "string" then
		ip = parseIPAddress(ip)
	elseif type(ip) == "cdata" then
		ip = ip:get()
	end
	local mac = self.arpTable[tostring(ip)]
	if type(mac) == "table" then
    --printf("arp entry exists")
		return mac.mac, mac.timestamp
	end
  if(type(mac) == "string" and mac == "requested")then
    -- rerequest, if already requested
    -- TODO: do this with a timeout, as now everytime lookup is called
    --  a new request might be sent
    --printf("resent")
    self.arpTable[tostring(ip)] = "pending"
  end
  if not self.arpTable[tostring(ip)] then
    --printf("no arp entry exists")
    self.arpTable[tostring(ip)] = "pending"
  end
	return nil
end

-- FIXME: this only sends a single request
function router_syncArp:blockingLookup(ip, timeout)
	local timeout = dpdk.getTime() + timeout
	repeat
		local mac, ts = self:lookup(ip)
		if mac then
			return mac, ts
		end
    -- we need to call handle, to react on incoming packets in the meantime
    self:handle()
    -- FIXME: delay was 1000 ms. WHY ??? In my opinion 100ms or less should be
    --  more than enough. RTT in LAN is usually less than 10ms
		dpdk.sleepMillisIdle(100)
	until dpdk.getTime() >= timeout
end

return mod

-- FIXME: TODO: on route to local network, route should be added with nhIP not with mac
