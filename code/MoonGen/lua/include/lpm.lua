local ffi = require "ffi"

--require "utils"
local band, lshift, rshift = bit.band, bit.lshift, bit.rshift
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local serpent = require "Serpent"
--local arp = require "proto.arp"
require "memory"
--local burst = require "burst"

ffi.cdef [[

struct rte_table_lpm_params {
	uint32_t n_rules;
	uint32_t entry_unique_size;
	uint32_t offset;
};
void * mg_table_lpm_create(void *params, int socket_id, uint32_t entry_size);
int mg_table_lpm_free(void *table);
int mg_table_entry_add_simple(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry);
int mg_table_lpm_entry_add(
	void *table,
  uint32_t ip,
  uint8_t depth,
	void *entry,
	int *key_found,
	void **entry_ptr);
int mg_table_lpm_lookup(
	void *table,
	struct rte_mbuf **pkts,
	uint64_t pkts_mask,
	uint64_t *lookup_hit_mask,
	void **entries);
int mg_table_lpm_lookup_big_burst(
	void *table,
	struct rte_mbuf **pkts,
	struct mg_bitmask* pkts_mask,
	struct mg_bitmask* lookup_hit_mask,
	void **entries);
int mg_table_lpm_entry_delete(
	void *table,
  uint32_t ip,
  uint8_t depth,
	int *key_found,
	void *entry);
void ** mg_lpm_table_allocate_entry_prts(uint16_t n_entries);
int printf(const char *fmt, ...);

int mg_table_lpm_lookup_big_burst2(
	void *table,
	struct rte_mbuf **pkts,
	struct mg_bitmask* in_mask,
	struct mg_bitmask* out_mask,
	void **entries);
int mg_table_lpm_lookup_big_burst2_queue(
	void *table,
	struct rte_mbuf **pkts,
	struct mg_bitmask* in_mask,
	struct mg_bitmask* out_mask,
  struct rte_ring *r,
	void **entries);
int mg_table_lpm_apply_route(
	struct rte_mbuf **pkts,
  struct mg_bitmask* pkts_mask,
	void **entries,
  uint16_t offset_entry,
  uint16_t offset_pkt,
  uint16_t size);
int mg_table_lpm_apply_route_single(
	struct rte_mbuf *pkt,
	void **entry,
  uint16_t offset_entry,
  uint16_t offset_pkt,
  uint16_t size);
int mg_table_lpm_lookup_single(
	void *table,
	struct rte_mbuf *pkt,
	void **entry);
]]


local mod = {}

local mg_lpm4Table = {}
mod.mg_lpm4Table = mg_lpm4Table
mg_lpm4Table.__index = mg_lpm4Table
mg_lpm4Table.__gc = function(self) print("collected") end

ffi.cdef [[
struct mg_lpm4Table_default_table_entry {
  uint8_t interface;
  struct mac_address mac_next_hop;
};
]]

--- Create a new LPM lookup table.
-- @param socket optional (default = socket of the calling thread), CPU socket,
--  where memory for the table should be allocated.
-- @param entry_ctype optional (default = "struct mg_lpm4Table_default_table_entry"
--  containing a 8 bit next hop interface number and a next hop mac address) cdata type of the routing table entries.
-- @return the table handler
function mod.createLpm4Table(socket, entry_ctype)
  socket = socket or select(2, dpdk.getCore())
  entry_ctype = entry_ctype or "struct mg_lpm4Table_default_table_entry"
    -- configure parameters for the LPM table
  local params = ffi.new("struct rte_table_lpm_params")
  params.n_rules = 1000
  params.entry_unique_size = ffi.sizeof(entry_ctype)
  --params.offset = 128 + 27+4
  params.offset = 128+ 14 + 12+4
  return setmetatable({
    table = ffi.C.mg_table_lpm_create(params, socket, ffi.sizeof(entry_ctype)),
    entry_ctype = entry_ctype
  }, mg_lpm4Table)
end

--- Free the LPM table.
-- @return 0 on success, error code otherwise
function mg_lpm4Table:free()
  return ffi.C.mg_table_lpm_free(self.table)
end

--- Add an entry to a Table.
-- @param addr IPv4 network address of the destination network.
-- @param depth number of significant bits of the destination network address
-- @param entry routing table entry (will be copied)
-- @return true if entry was added without error
function mg_lpm4Table:addEntry(addr, depth, entry)
  return 0 == ffi.C.mg_table_entry_add_simple(self.table, addr, depth, entry)
end

--- Perform IPv4 route lookup for a burst of packets.
-- This should not be used for single packet lookup, as ist brings
-- a significant penalty for bursts <<64
-- @param packets Array of mbufs (bufArray), for which the lookup will be performed
-- @param mask bitmask, for which packets the lookup should be performed
-- @param hitMask Bitmask, where the bits corresponding to the routed packets
--  will be set to 1 and the bits corresponding to the packets, where no route
--  could be found will be cleared. NOTE: bits corresponding to packets, where
--  no lookup was performed will not be touched
-- @param entries Preallocated routing entry Pointers
-- @return always 0
function mg_lpm4Table:lookupBurst(packets, mask, hitMask, entries)
  -- FIXME: I feel uneasy about this cast, should this cast not be
  --  done implicitly?
  return ffi.C.mg_table_lpm_lookup_big_burst2(self.table, packets.array, mask.bitmask, hitMask.bitmask, ffi.cast("void **",entries.array))
end

--- Perform IPv4 route lookup for a burst of packets.
-- Same as mg_lpm4Table:lookupBurst(...) but additionally, all packets, where
-- no route could be found will be enqueued to a fast pipe, or freed, if this
-- queue is full.
-- @param pipe fastPipe to which packets will be sent, where no route could
--  be found
-- @return always 0
function mg_lpm4Table:lookupBurst_pipe(packets, mask, hitMask, pipe, entries)
  -- FIXME: I feel uneasy about this cast, should this cast not be
  --  done implicitly?
  return ffi.C.mg_table_lpm_lookup_big_burst2_queue(self.table, packets.array, mask.bitmask, hitMask.bitmask, pipe.ring, ffi.cast("void **",entries.array))
end

--- Perform IPv4 route lookup for a single packet.
-- @param packet mbuf containing the packet, for which the lookup should be performed
-- @param entries Preallocated routing entry Pointers (not a single entry, but
--  an array, as received with mg_lpm4Table:allocateEntryPtrs(n))
-- @return 1 on success, 0 when no route was found
function mg_lpm4Table:lookup_single(packet, entry)
  return (ffi.C.mg_table_lpm_lookup_single(self.table, packet, ffi.cast("void **",entry.array)) == 1)
end

function mg_lpm4Table:__serialize()
	return "require 'lpm'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('lpm').mg_lpm4Table"), true
end

--- Allocates an LPM table entry
-- @return The newly allocated entry
function mg_lpm4Table:allocateEntry()
  return ffi.new(self.entry_ctype)
end
--
--- Allocates an LPM table entry and return a pointer to it
--- Allocates an LPM table entry
-- @return Pointer to he newly allocated entry
function mg_lpm4Table:allocateEntry_ptr()
  return ffi.new(self.entry_ctype .. "[1]")
end

local mg_lpm4EntryPtrs = {}

--- Allocates an array of pointers to routing table entries
-- This is used during burst lookup, to store references to the
-- result entries.
-- @param n Number of entry pointers
-- @return Wrapper table around the allocated array
function mg_lpm4Table:allocateEntryPtrs(n)
  -- return ffi.C.mg_lpm_table_allocate_entry_prts(n)
  return setmetatable({
    array = ffi.new(self.entry_ctype .. "*[?]", n)
  }, mg_lpm4EntryPtrs)
end

function mg_lpm4EntryPtrs:__index(k)
	if type(k) == "number" then
    return self.array[k - 1]
  else
    return mg_lpm4EntryPtrs[k]
  end
end

function mg_lpm4EntryPtrs:__newindex(x, y)
  self.array[x-1] = y
end

--- Apply routes to packets
-- Copies the mac addresses found in the entries to the destination mac address
-- field of the corresponding packets
-- @param pkts buffer array, containig packets
-- @param mask bitMask describing for whick packets the operation should be done
-- @param entries routing table entries for the packets
-- @packets entrOffset optional (default = 1 matching the default entry_ctype)
--  Offset in bytes where to find the mac address in the entry
-- @return always 0
function mod.applyRoute(pkts, mask, entries, entryOffset)
  entryOffset = entryOffset or 1
  return ffi.C.mg_table_lpm_apply_route(pkts.array, mask.bitmask, ffi.cast("void **", entries.array), entryOffset, 128, 6)
end

--- Apply routes to a single packet
-- Same as mod.applyRoute(), but for a single packet
-- @param pkt mbuf containing the packet
-- @param entries Routing entry Pointers (not a single entry, but
--  an array, as received with mg_lpm4Table:allocateEntryPtrs(n))
-- @packets entrOffset optional (default = 1 matching the default entry_ctype)
--  Offset in bytes where to find the mac address in the entry
-- @return always 0
function mod.applyRoute_single(pkt, entry, entryOffset)
  entryOffset = entryOffset or 1
  return ffi.C.mg_table_lpm_apply_route_single(pkt, ffi.cast("void **",entry.array), entryOffset, 128, 6)
end

-- FIXME: this should not be in LPM module. but where?
--- Decrements the IP TTL field of all masked packets by one.
--  out_mask masks the successfully decremented packets (TTL did not reach zero).
-- @param pkts buffer array
-- @param in_mask bitmask, for which packets the operation should be performed
-- @param out_Mask Bitmask, where the bits corresponding to packets, where TTL
--  was decremented successfully will be set to 1 and the bits corresponding to
--  the packets, where the TTL reached 0 will be set to 0.
--  NOTE: bits corresponding to packets, where no operation was performed will
--  not be touched
function mod.decrementTTL(pkts, in_mask, out_mask, ipv4)
  ipv4 = ipv4 == nil or ipv4
  if ipv4 then
    for i, pkt in ipairs(pkts) do
      if in_mask[i] then
        local ipkt = pkt:getIPPacket()
        local ttl = ipkt.ip4:getTTL()
        if(ttl > 0)then
          ttl = ttl - 1;
          ipkt.ip4:setTTL(ttl)
          out_mask[i] = 1 
        else
          out_mask[i] = 0
        end
      end
    end
  else
    errorf("TTL decrement for ipv6 not yet implemented")
  end
end

ffi.cdef[[
void mg_ipv4_decrement_ttl(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask
    );

void mg_ipv4_decrement_ttl_queue(
    struct rte_mbuf **pkts,
    struct mg_bitmask * in_mask,
    struct mg_bitmask * out_mask,
    struct rte_ring *r
    );
]]

-- FIXME: this should not be in LPM module. but where?
--- Decrements the IP TTL field of all masked packets by one.
-- This is the same as mod.decrementTTL(...) but uses a faster C implementation
function mod.decrementTTLC(pkts, in_mask, out_mask, ipv4)
  ipv4 = ipv4 == nil or ipv4
  if ipv4 then
    ffi.C.mg_ipv4_decrement_ttl(pkts.array, in_mask.bitmask, out_mask.bitmask);
  else
    errorf("TTL decrement for ipv6 not yet implemented")
  end
end

--- Decrements the IP TTL field of all masked packets by one.
-- This is the same as mod.decrementTTLC(...) but additionally, all packets,
-- where the TTL reached 0 will be enqueued to a fast pipe, or freed, if this
-- queue is full.
-- @param fastPipe fastPipe to which packets will be sent, where the TTL reached 0
function mod.decrementTTL_pipeC(pkts, in_mask, out_mask, fastPipe, ipv4)
  ipv4 = ipv4 == nil or ipv4
  if ipv4 then
    ffi.C.mg_ipv4_decrement_ttl_queue(pkts.array, in_mask.bitmask, out_mask.bitmask, fastPipe.ring);
  else
    errorf("TTL decrement for ipv6 not yet implemented")
  end
end

--- Decrements the IP TTL field of a packet by one.
-- This is the same as mod.decrementTTL(...) but only works on one packet
-- @param pkt mbuf containing the packet
-- @param ipv4 optional (default = true) specifies, if true, the packet is
--  assumed to be ipv4 otherwise it is assumed to be ipv6. currently only ipv4
--  packets are supported
-- @return true if TTL was decremented successfully, false if TTL reached 0
function mod.decrementTTL_single(pkt, ipv4)
  ipv4 = ipv4 == nil or ipv4
  if ipv4 then
    -- TODO: C implementation might be faster...
    local ipkt = pkt:getIPPacket()
    local ttl = ipkt.ip4:getTTL()
    -- according to RFC 1812 we should discard the packet, as soon as we
    -- decrement to 0. So we check for ttl > 1 here:
    if(ttl > 1)then
      ttl = ttl - 1;
      ipkt.ip4:setTTL(ttl)
      return true
    else
      return false
    end
  else
    errorf("TTL decrement for ipv6 not yet implemented")
  end
end

return mod
