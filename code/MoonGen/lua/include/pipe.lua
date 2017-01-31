local mod = {}

local memory	= require "memory"
local ffi		= require "ffi"
local serpent	= require "Serpent"
local dpdk		= require "dpdk"

ffi.cdef [[
	// dummy
	struct spsc_ptr_queue { };

	struct spsc_ptr_queue* make_pipe();
	void enqueue(struct spsc_ptr_queue* queue, void* data);
	void* try_dequeue(struct spsc_ptr_queue* queue);
	void* peek(struct spsc_ptr_queue* queue);
	uint8_t pop(struct spsc_ptr_queue* queue);
	size_t count(struct spsc_ptr_queue* queue);
]]

local C = ffi.C


mod.slowPipe = {}
local slowPipe = mod.slowPipe
slowPipe.__index = slowPipe

--- Create a new slow pipe.
-- A pipe can only be used by exactly two tasks: a single reader and a single writer.
-- Slow pipes are called slow pipe because they are slow (duh).
-- Any objects passed to it will be *serialized* as strings.
-- This means that it supports arbitrary Lua objects following MoonGens usual serialization rules.
-- Use a 'fastCPipe' if you need fast inter-task communication. Fast pipes are restricted to LuaJIT FFI objects.
function mod:newSlowPipe()
	return setmetatable({
		pipe = C.make_pipe()
	}, slowPipe)
end

function slowPipe:send(...)
	local vals = serpent.dump({ ... })
	local buf = memory.alloc("char*", #vals + 1)
	ffi.copy(buf, vals)
	C.enqueue(self.pipe, buf)
end

function slowPipe:tryRecv(wait)
	while wait >= 0 do
		local buf = C.try_dequeue(self.pipe)
		if buf ~= nil then
			local result = loadstring(ffi.string(buf))()
			memory.free(buf)
			return unpackAll(result)
		end
		wait = wait - 10
		if wait < 0 then
			break
		end
		dpdk.sleepMicros(10)
	end
end

function slowPipe:recv()
	local function loop(...)
		if not ... then
			return loop(self:tryRecv(10))
		else
			return ...
		end
	end
	return loop()
end

function slowPipe:count()
	return tonumber(C.count(self.pipe))
end

function slowPipe:__serialize()
	return "require'pipe'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('pipe').slowPipe"), true
end


ffi.cdef [[

// this struct definition will not work for actual use in lua,
// because preprocessor code was removed
struct rte_ring {
	char name[32];    /**< Name of the ring. */
	int flags;                       /**< Flags supplied at creation. */

	/** Ring producer status. */
	struct prod {
		uint32_t watermark;      /**< Maximum items before EDQUOT. */
		uint32_t sp_enqueue;     /**< True, if single producer. */
		uint32_t size;           /**< Size of ring. */
		uint32_t mask;           /**< Mask (size-1) of ring. */
		volatile uint32_t head;  /**< Producer head. */
		volatile uint32_t tail;  /**< Producer tail. */
	} prod;

	/** Ring consumer status. */
	struct cons {
		uint32_t sc_dequeue;     /**< True, if single consumer. */
		uint32_t size;           /**< Size of the ring. */
		uint32_t mask;           /**< Mask (size-1) of ring. */
		volatile uint32_t head;  /**< Consumer head. */
		volatile uint32_t tail;  /**< Consumer tail. */
	} cons;

	void * ring[0];
};



struct rte_ring *rte_ring_create(const char *name, unsigned count,
				 int socket_id, unsigned flags);

unsigned mg_queue_count_export(const struct rte_ring *r);
int mg_queue_dequeue_export(struct rte_ring *r, void **obj_p);
int mg_queue_enqueue_export(struct rte_ring *r, void *obj);
]]

-- XXX NOTE:
-- It is very hard to make a fast generic queue, which supports arbitary data
-- and blends in nicely in LUA.
-- This is because of the following reasons:
--  - It is not possible to transfer references to LUA objects, only ctype
--    objects can easily be transferred
--  - To transfer Lua objects some conversion is needed, which takes time
--  - Even for passing ctype objects, we lose all type information.
--  - To explicitly store type information with the reference costs extra
--    time + memory
-- Because of this, this is a relatively pure wrapper around rte_ring, which
-- only supports luaJIT ctype objects
-- TODO: Add features:
--  => integrate RED
--  -> integrate watermark support
--  -> implement dropping policy based on watermarks?

local mg_fastCPipe = {}
mod.mg_fastCPipe = mg_fastCPipe
mg_fastCPipe.__index = mg_fastCPipe

function mg_fastCPipe:__serialize()
	return "require 'pipe'; return " .. serpent.addMt(serpent.dumpRaw(self), "require('pipe').mg_fastCPipe"), true
end


local cpipe_count = 0
--- Creates a new fast Pipe.
--  Only LuaJIT ctype objects can be transferred with
--  this pipe. Multiple consumers, as well as multiple producers are supported,
--  if enabled. However you should try to stick with single producer and
--  consumer, for lockless behavior.
--  @param args optional A table of named arguments:
--    - size: maximum number of entries in the queue will be (size - 1)
--      (default = 64)
--    - multipleConsumers: if true, the queue will enable multiple consumer
--      safe enqueue/dequeue operations
--      (default = false)
--    - multipleProducers: if true, the queue will enable multiple producer
--      safe enqueue/dequeue operations
--      (default = false)
--    - socket: NUMA CPU socket, where to allocate storage for the queue
--      (default = CPU socket of the calling thread)
function mod.newFastCPipe(args)
  args = args or {}
  args.size = args.size or 64
  args.multipleConsumers = args.multipleConsumers or false
  args.multipleProducers = args.multipleProducers or false
  args.socket = args.socket or select(2, dpdk.getCore())
  if(bit.band(args.size-1, args.size) ~= 0)then
    errorf("Queue size must be a power of two")
  end

  local flags = 0
  if(args.multipleConsumers == false) then
    flags = bit.bor(flags, 2)
  end
  if(args.multipleConsumers == false) then
    flags = bit.bor(flags, 1)
  end
  -- somehow dpdk does not allow, using the same name twice, so we have to use a different one every time
  local ring = ffi.C.rte_ring_create("mg_ring" .. tostring(cpipe_count), args.size, args.socket, flags)
  cpipe_count = cpipe_count + 1
  if(ring == nil)then
    errorf("ERROR creating ring")
    -- TODO: implement wrapper around rte_errno.h
    --  this will then also obsolete error.lua
  end


  return setmetatable({
    ring = ring,
    size = args.size
  }, mg_fastCPipe)
end

--- Free the fastPipe.
function mg_fastCPipe:free()
  ffi.C.rte_free(self.ring)
end

--- Enqueue a ctype object.
-- @param object object of type cdata to be enqueued
-- @return number of objects enqueued (i.e. 0 if not enqueued, 1 if enqueued)
function mg_fastCPipe:enqueue(object)
  return ffi.C.mg_queue_enqueue_export(self.ring, object)
end

--- Dequeue a ctype object.
-- @param ctype optonal (default = "struct rte_mbuf*") The type of the object
--  to be returned. The dequeued object will be casted to this type.
-- @return the dequeued object casted to the specified type
function mg_fastCPipe:dequeue(ctype)
  ctype = ctype or "struct rte_mbuf*"
  local object = ffi.new("void *")
  local objects = ffi.new("void*[1]")
  objects[0] = object
  local result = ffi.C.mg_queue_dequeue_export(self.ring, objects)
  if (result == 0)then
    return ffi.cast(ctype, objects[0])
  else
    return nil
  end
end

--- Dequeue an mbuf.
-- Same as dequeue(ctype), but the dequeued object will always be casted to
--  "struct rte_mbuf*"
function mg_fastCPipe:dequeueMbuf()
  --printf("dm")
  local object = ffi.new("void *")
  local objects = ffi.new("void*[1]")
  objects[0] = object
  --printf("td")
  local result = ffi.C.mg_queue_dequeue_export(self.ring, objects)
  --printf("tdf")
  if (result == 0)then
    --printf("k")
    return ffi.cast("struct rte_mbuf*", objects[0])
  else
    return nil
  end
end

--- Enqueue mbufs.
-- Enqueues a set of Mbufs, specified by a bitmask. Non enqueueable mbufs
-- will be freed.
-- @param bufArray containing pointers to mbufs to be enqueued
-- @param bitmask bitMask specifying the mbufs to be enqueued
function mg_fastCPipe:enqueueMbufsMask(objects, bitmask)
  --printf("enqburst")
  -- TODO: C implementation
  --bitmask:printout();
  for i,v in ipairs(bitmask) do
    if v then
      --printf("sin enq i = %u", i)
      if(objects[i] == nil)then
        print "NIL HERE"
      end
      if (ffi.C.mg_queue_enqueue_export(self.ring, objects[i]) ~= 0)then
        --printf("no enqueue possible")
        objects[i]:free();
      end
    end
  end
end

return mod

