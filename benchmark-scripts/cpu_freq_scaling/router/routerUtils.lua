local lpm = require "lpm"

--- Prints colorized text.
-- @param str text to be printed
-- @param color a string describing the color in which the text is printed.
--  supported colors are:
--    - red
--    - green
--    - yellow
--    - blue
--    - mangenta
--    - cyan
--    - white
function printfColor(str, color, ...)
  local colorcode
  if color == "red" then
    colorcode = "\x1B[31m"
  end
  if color == "green" then
    colorcode = "\x1B[32m"
  end
  if color == "yellow" then
    colorcode = "\x1B[33m"
  end
  if color == "blue" then
    colorcode = "\x1B[34m"
  end
  if color == "mangenta" then
    colorcode = "\x1B[35m"
  end
  if color == "cyan" then
    colorcode = "\x1B[36m"
  end
  if color == "white" then
    colorcode = "\x1B[37m"
  end
  printf(colorcode .. str .. "\x1B[0m", ...)
end

--- Convert a routing table entry into a string.
-- @param route the route (a lua table, not a LPM table entry)
-- @return a well formated string describing the route
function getRouteString(route)
  local str = ""
  str = str .. route.networkIP
  str = str .. "/"
  str = str .. route.networkPrefix
  str = str .. " via "
  if(route.nhMAC) then
    str = str .. route.nhMAC
  else
    str = str .. route.nhIPv4
  end
  str = str .. " on "
  str = str .. route.nhPort
  return str
end


--- Check if a route is invalid.
-- This checks a route against several sanity check and against the router
-- configuration.
-- @param route the route
-- @param config router configuration table
-- @return a nice string with an error message, if the route is invalid, nil otherwise.
function isRouteInvalid(route, config)
  if(not route.nhPort) then
    return "missing nh port"
  end
  if(not route.networkIP) then
    return "missing network IP"
  end
  if(not route.networkPrefix) then
    return "missing network Prefix"
  end
  if((not route.nhIPv4) and (not route.nhMAC)) then
    return "missing next hop address"
  end
  if(not parseIP4Address(route.networkIP))then
    return "Invalid IPv4 network address"
  end
  if(route.networkPrefix > 32 or route.networkPrefix < 0) then
    return "network Prefix not in range 0...32"
  end
  if(not config.ports[route.nhPort])then
    return "specified nhPort does not exist"
  end
  if(route.nhIPv4) then
    if(not parseIP4Address(route.nhIPv4)) then
      return "Invalid IPv4 next hop address"
    end
  end
  if(route.nhMAC) then
    if(not parseMacAddress(route.nhMAC)) then
      return "Invalid next hop MAC address"
    end
  end
  return nil
end


--- Add routes to an LPM table
-- this extends the lpmtable "class" with one method
-- @param routes list of routes
-- @param ports list containing port descriptions of available router ports
-- @param arpLookupFun function which will be used to perform arp lookups with
--  the arguments ip address and timeout in seconds
-- @return the LPM routing table, to which the rules have been added
function lpm.mg_lpm4Table:addRoutesFromTable(routes, ports, arpLookupFun)
  local lpmTable = self
  -- add all routes:
  local entry = lpmTable:allocateEntry()
  for i, route in pairs(routes) do
    printf(" adding %s: %s", i, getRouteString(route))
    -- Order in which routes are added, does not matter. the dpdk algorithm
    -- will overwrite overlapping existing rule entries only, if the new depth
    -- is more specific than the existing rule depth
    entry.interface = ports[route.nhPort].device.id
    if(route.nhMAC ~= nil) then
      -- we have a static mac address given
      -- so we use this:
      entry.mac_next_hop = parseMacAddress(route.nhMAC)
      --printf("mac static %s", route.nhMAC)
      local state = lpmTable:addEntry(parseIPAddress(route.networkIP), route.networkPrefix, entry)
      --printf("-> nh mac = %s", entry.mac_next_hop:getString())
      if(not state) then
        errorf("Failed to add entry to LPM table")
      end
    else
      -- we have to make an ARP lookup
      local mac, _ = arpLookupFun(parseIPAddress(route.nhIPv4), 1)
      if(mac) then
        entry.mac_next_hop = parseMacAddress(mac)
        --printf("mac dynamic %s", mac)
        local state = lpmTable:addEntry(parseIPAddress(route.networkIP), route.networkPrefix, entry)
        --printf("-> nh mac = %s", entry.mac_next_hop:getString())
        if(not state) then
          errorf("Failed to add entry to LPM table")
        end
      else
        printf("  [WARNING] could not resolve MAC address for route to %s", route.nhIPv4)
      end
    end
  end
  return lpmTable
end

