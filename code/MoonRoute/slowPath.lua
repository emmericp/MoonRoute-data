require "routerUtils"
local lpm     = require "lpm"
local memory	= require "memory"
local rshift = bit.rshift
local icmp = require "proto.icmp"
local ffi = require "ffi"

local router_slowPath = {}
mod.router_slowPath = router_slowPath
router_slowPath.__index = router_slowPath

local mod = {}


function router_slowPath:updateRoutingTable()
  print "updating routing table"
  -- i currently make this blocking.
  -- if this will be implemented non blocking, a lot of things have to be
  -- considered. e.g. what will happen, when an other forceUpdate will come,
  -- while the table is still beeing updated
  -- => ah we could just leave the forceLpmUpdate high and wait until we
  -- finished updating.. never mind
  -- TODO: make a routing table class with methods like linux constructor, add to lpm, etc...
  local lpmTable_pending = lpm.createLpm4Table()
  -- add the static routes from the configuration:
  printf("add static:")
  lpmTable_pending:addRoutesFromTable(self.config.routes, self.config.ports, function(ip) return self.config.arpInstance:blockingLookup(ip, 0.5) end)
  -- add the dynamic routes:
  printf("add dynamic:")
  lpmTable_pending:addRoutesFromTable(self.config.dynamicRoutes, self.config.ports, function(ip) return self.config.arpInstance:blockingLookup(ip, 0.5) end)
  if(config["enableVirtualInterfaces"] and config["useLinuxRoutingTable"]) then
    printf("add linux:")
    local linuxRoutes = getLinuxRoutes(config.virtualDevices)
    lpmTable_pending:addRoutesFromTable(linuxRoutes, self.config.ports, function(ip) return self.config.arpInstance:blockingLookup(ip, 0.5) end)
    config["linuxRoutes"] = linuxRoutes
  end
  printf("added all routes :)")

  -- deploy the new routing table to all fast path cores:
  local cmd = {command = "NewTable", sequenceNr = self.cmdSequenceNr, lpmTable = lpmTable_pending}
  for c, core in pairs(self.cores) do
    printf("send update to core %d", c)
    core.cmdRxQueue:send(cmd)
    repeat
      local reply = core.cmdTxQueue:tryRecv(10) or ""
      -- TODO / FIXME if more than one message is supported,
      --  and/or if the cmd sending is done asynchronously, which means,
      --  that there can be more than one command pending, then we also
      --  have to process other cmds here
    until (reply.command == "ACK" and reply.sequenceNr == self.cmdSequenceNr)
  end
  -- all cores have the new routing table :) yay
  -- so we can free the old one:
  self.lpmTable_active:free()
  -- and switch to the new table
  self.lpmTable_active = lpmTable_pending

  -- increment cmd Sequence number:
  self.cmdSequenceNr = self.cmdSequenceNr + 1
  print "updating routing table -> done"
end

function router_slowPath:processPacket(pkt)
  -- We have to identify the source port of the packet by MAC address:
  -- TODO: make a byte comparison here instead of converting everything
  --  to string
  local mac_str = pkt:getEthernetPacket().eth:getDstString():lower()
  local port = nil
  for _, p in pairs(self.config.ports) do
    if(p.mac:lower() == mac_str) then
      port = p
      break
    end
  end
  if (port == nil) then
    errorf("ERROR: received a packet, with an unknown dst MAC of %s (note: broadcast macs are not supported in slow path)", mac_str)
  end
  local ttl = pkt:getIPPacket().ip4:getTTL()
  if(lpm.decrementTTL_single(pkt)) then
    if(self.lpmTable_active:lookup_single(pkt, self.lpmEntry)) then
      lpm.applyRoute_single(pkt, self.lpmEntry, nil)
      self.distributor:send_single(pkt, self.lpmEntry)
      pkt:free()
    else
      no_route = true
      -- Fast path could not find a route to the destination
      -- Now lets find out, if we can find one... :)
      -- Concept:
      -- 1. let packages to local networks be forwarded to slowpath (they will drop out
      --  because there is no lpm entry)
      -- 2. slow path will detect, that the packets are destined to local networks
      -- 3. ARP lookup will be performed (will block slow path ... meh :( )
      --    -> maybe slow path will need a additional queue to store packets, which
      --    are waiting for something
      -- 4. on success forward the packet + add a /32 entry to the LPM table
      --  -> future packets will be handled in fast path
      --
      -- we check, if the packet should be routed to a local subnet:
      local packet_dst_ip = pkt:getIPPacket().ip4:getDst()
      for portname, port in pairs(self.config.ports) do
        -- TODO: performance: cache IP address for each port
        local port_ip = parseIPAddress(port.ipv4)
        -- TODO: also cache netmask in mask format
        local netmask = rshift(0x80000000,port.ipv4Prefix - 1) - 1
        netmask = util_bnot32(netmask)
        netmask = util_band32(netmask,   0xffffffff)
        --printf("mask: %x, packet ip: %x, port ip: %x", netmask, packet_dst_ip, port_ip)
        if((packet_dst_ip == port_ip) and port.virtualDev) then
          -- FIXME: packets destined to other local interfaces are not routed!!
          local ippkt = pkt:getIPPacket()
          ippkt.ip4:calculateChecksum()
          port.virtualDev:txSingle(pkt)
          no_route = false
        elseif(util_band32(packet_dst_ip, netmask) == util_band32(port_ip, netmask)) then
          printf("route to local subnet!!")
          -- we have to make an ARP lookup
          local mac, _ = self.config.arpInstance:blockingLookup(packet_dst_ip, 0.5)
          if(mac) then
            printf("arp found")
            -- there really exists a host in our local subnet with the
            -- destination ip :)
            -- create an entry for the distributor
            local rentry = self.lpmTable_active:allocateEntry_ptr()
            rentry[0].interface = port.device.id
            rentry[0].mac_next_hop = parseMacAddress(mac)
            self.lpmEntry[1] = rentry
            lpm.applyRoute_single(pkt, self.lpmEntry, nil)
            self.distributor:send_single(pkt, self.lpmEntry)
            no_route = false
            printf("sent packet to local network")

            -- now we add a route to this host to the routing table:
            -- FIXME: what to do, if  route already exists?
            -- FIXME: use insert here
            local ridx = #routes + 1
            -- FIXME FIXME FIXME: shouldnt this be self.config.dynamic_routes
            self.routes[ridx] = {}
            self.routes[ridx]["nhPort"] = portname
            self.routes[ridx]["nhIPv4"] = pkt:getIPPacket().ip4:getDstString()
            self.routes[ridx]["networkIP"] = pkt:getIPPacket().ip4:getDstString()
            self.routes[ridx]["networkPrefix"] = 32
            self.config.forceLpmUpdate = true
          else
            printf("no arp")
          end
          break
        end
      end
      if(no_route)then
        -- No route to destination, so we drop the packet
        pkt:free()
      end
    end
  else
    -- ICMP time exceeded
    local header_size = pkt:getIPPacket().ip4:getHeaderLength()*4
    -- ethernet + ip + icmp + icmpunused + ip + 8 (payload data)
    local icmpPktLen = 14 + 20 + 4 + 4 + header_size + 8
    self.icmpBufs:alloc(icmpPktLen)
    local icmpPkt = self.icmpBufs[1]:getIcmpPacket()
    icmpPkt:fill{
      ethSrc=port.device:getMac(),
      ip4Dst=pkt:getIPPacket().ip4:getSrc(),
      -- The IP address of the receiving port :)
      ip4Src=parseIPAddress(port.ipv4),
      icmpType=icmp.TIME_EXCEEDED_TTL_EXPIRED.type,
      icmpCode=icmp.TIME_EXCEEDED_TTL_EXPIRED.code,
      pktLength=icmpPktLen
    }
    -- Sorry for the ugly code, however currently MoonGen is not really
    -- usable for accessing the Payload of packets...
    -- TODO: crop the 8 to avoid memory overflow
    icmpPkt.icmp:setPayloadFromPtr(ffi.cast("void*", pkt:getIPPacket().ip4), header_size + 8)
    icmpPkt.icmp:calculateChecksum(4+4+header_size + 8)
    self.icmpBufs:offloadIPChecksums()
    -- we have to route the packet:
    if(self.lpmTable_active:lookup_single(self.icmpBufs[1], self.lpmEntry)) then
      lpm.applyRoute_single(self.icmpBufs[1], self.lpmEntry, nil)
      self.distributor:send_single(self.icmpBufs[1], self.lpmEntry)
    else
      self.icmpBufs[1]:free()
    end
    -- packet will be dropped:
    pkt:free()
  end
end

function mod.createSlowPath(cores, config, lpmTable, distributor)
  local entry = lpmTable:allocateEntryPtrs(1)
  local icmpMemPool = memory.createMemPool()
  local icmpBufs = icmpMemPool:bufArray(1)
  return setmetatable({
    cores = cores,
    config = config,
    distributor = distributor,
    lpmTable_active = lpmTable,
    routes = {},
    lpmEntry = entry,
    icmpMemPool = icmpMemPool,
    icmpBufs = icmpBufs,
    cmdSequenceNr = 0
  }, router_slowPath)
end

function router_slowPath:handle(lpmTable, distributor, cores, config)
  for c, core in pairs(self.cores) do
    -- handle incoming packets from this core
    --printf("try dequeue on core %d", c)
    local pkt = core.slowQueue:dequeueMbuf()
    if pkt then
      printf("slow path rxed from core %d", c)
      self:processPacket(pkt)
      --printf(" slow path done processing")
    end
  end
  -- if neccessary we propagate routing table updates to the fast path cores:
  if(self.config.forceLpmUpdate) then
    self:updateRoutingTable()
    self.config.forceLpmUpdate = false
  end
  self.distributor:handleTimeouts()
end

return mod
