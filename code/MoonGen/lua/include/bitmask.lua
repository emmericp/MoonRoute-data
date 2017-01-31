local ffi = require "ffi"
ffi.cdef [[
struct mg_bitmask{
  uint16_t size;
  uint16_t n_blocks;
  uint64_t mask[0];
};
struct mg_bitmask * mg_bitmask_create(uint16_t size);
void mg_bitmask_free(struct mg_bitmask * mask);
void mg_bitmask_set_n_one(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_set_all_one(struct mg_bitmask * mask);
void mg_bitmask_clear_all(struct mg_bitmask * mask);
uint8_t mg_bitmask_get_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_set_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_clear_bit(struct mg_bitmask * mask, uint16_t n);
void mg_bitmask_and(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_xor(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_or(struct mg_bitmask * mask1, struct mg_bitmask * mask2, struct mg_bitmask * result);
void mg_bitmask_not(struct mg_bitmask * mask1, struct mg_bitmask * result);
]]


mod = {}

local mg_bitMask = {}
--mg_bitMask.__index = mg_bitMask

--- Create a Bitmask.
-- The mask is internally built from blocks of 64bit integers. Hence a Bitmask
-- of a size <<64 yields significant overhead
-- @param size Size of the bitmask in number of bits
-- @return Wrapper table around the bitmask
function mod.createBitMask(size)
  return setmetatable({
    bitmask = ffi.C.mg_bitmask_create(size)
  }, mg_bitMask)
end

--- Free the Bitmask.
function mg_bitMask:free()
  ffi.C.mg_bitmask_free(self.bitmask)
end

--- sets the first n bits in a bitmask to 1.
-- other bits remain unchanged
function mg_bitMask:setN(n)
  ffi.C.mg_bitmask_set_n_one(self.bitmask, n)
  return self
end

--- sets all bits in a bitmask to 0.
function mg_bitMask:clearAll()
  ffi.C.mg_bitmask_clear_all(self.bitmask)
  return self
end

--- sets all bits in a bitmask to 1.
function mg_bitMask:setAll()
  ffi.C.mg_bitmask_set_all_one(self.bitmask)
  return self
end

--- Index metamethod for mg_bitMask.
-- @param x Bit index. Index starts at 1 according to the LUA standard (1 indexes the first bit in the bitmask)
-- @return For numeric indices: true, when corresponding bit is 1, false otherwise.
function mg_bitMask:__index(x)
  -- access
  --print(" bit access")
  --print(" type " .. type(x))
  --print(" x = " .. tostring(x))
  if(type(x) == "number") then
    return (ffi.C.mg_bitmask_get_bit(self.bitmask, x - 1) ~= 0)
  else
    return mg_bitMask[x]
  end
end

--- Newindex metamethod for mg_bitMask.
-- @param x Bit index. Index starts at 1 according to the LUA standard (1 indexes the first bit in the bitmask)
-- @param y Assigned value to the index (bit is cleared for y==0 and set otherwise)
function mg_bitMask:__newindex(x, y)
  --print ("new index")
  if(y == 0) then
    -- clear bit
    --print("clear")
    return ffi.C.mg_bitmask_clear_bit(self.bitmask, x - 1)
  else
    -- set bit
    --print("set")
    return ffi.C.mg_bitmask_set_bit(self.bitmask, x - 1)
  end
end

do
	local function it(self, i)
		if i >= self.bitmask.size then
			return nil
		end
		return i + 1, self[i+1]
	end

	function mg_bitMask.__ipairs(self)
		return it, self, 0
	end
end

--- Print a bitmask.
-- Each bit will be printed into one line, with bit number and its value
function mg_bitMask:printout()
  for i, v in ipairs(self) do
    if(v) then
      printf("%d->1", i)
    else
      printf("%d->0", i)
    end
  end
end

--- Print a bitmask in compact form.
-- Prints the bitmask in one line (only the values are printed)
function mg_bitMask:printoutcompact()
  for i, v in ipairs(self) do
    if(v) then
      io.write("1")
    else
      io.write("0")
    end
  end
  print ""
end

--- Bitwise and.
--  result = mask1 band mask2
-- @param mask1
-- @param mask2
-- @param result an initialized bitmask, in which the result will be written
-- @return result
function mod.band(mask1, mask2, result)
  ffi.C.mg_bitmask_and(mask1.bitmask, mask2.bitmask, result.bitmask)
  return result
end

--- Bitwise or.
--  result = mask1 bor mask2
-- @param mask1
-- @param mask2
-- @param result an initialized bitmask, in which the result will be written
-- @return result
function mod.bor(mask1, mask2, result)
  ffi.C.mg_bitmask_or(mask1.bitmask, mask2.bitmask, result.bitmask)
  return result
end

--- Bitwise xor.
--  result = bask1 bxor mask2
-- @param mask1
-- @param mask2
-- @param result an initialized bitmask, in which the result will be written
-- @return result
function mod.bxor(mask1, mask2, result)
  ffi.C.mg_bitmask_xor(mask1.bitmask, mask2.bitmask, result.bitmask)
  return result
end

-- Bitwise not.
--  result = not mask
-- @param mask
-- @param result an initialized bitmask, in which the result will be written
-- @return result
function mod.bnot(mask, result)
  ffi.C.mg_bitmask_not(mask.bitmask, result.bitmask)
  return result
end

return mod
