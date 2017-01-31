config = {ports = {}, routes = {}}


-- GENERAL CONFIGURATION
config["txQueueSize"] = 128
config["txQueueTimeout"] = 0.0001
config["rxBurstSize"] = 128
config["addRoutesToLocalNetworks"] = false
config["telnetEnable"] = false
config["telnetPort"] = 23
config["telnetBindIP"] = "0.0.0.0"
config["slowPathQueueSize"] = 64


-- PORT CONFIGURATION
-- configuration, which applies to all ports
config["fastPathCores"] = {1}

-- port wise configuration
ports = {}

ports["Port1"] = {
  mac = "A0:36:9F:3B:6D:52",
  ipv4 = "10.0.2.1",
  ipv4Prefix = 24,
  direction = "inout",
}
ports["Port2"] = {
  mac = "A0:36:9F:3B:6D:50",
  ipv4 = "10.0.1.1",
  ipv4Prefix = 24,
  direction = "inout"
}


-- STATIC ROUTES CONFIGURATION
routes = {}

 routes["Route1"] = {
   nhPort = "Port2",
   -- if a nhMAC field is present, it has priority over the nhIPv4 field
   --nhMAC = "A0:36:9f:3b:6d:77",
   nhMAC = "a0:36:9f:3b:5b:6c",
   networkIP = "0.0.0.0",
   networkPrefix = 1
 }
 routes["Route2"] = {
   nhPort = "Port2",
   --nhMAC = "A0:36:9f:3b:6d:44",
   nhMAC = "a0:36:9f:3b:5b:6c",
   --nhIPv4 = "10.0.1.5",
   networkIP = "128.0.0.0",
   networkPrefix = 1
 }
-- for i = 0, 255 do
--   routes[#routes + 1] = {
--     nhPort = "Port2",
--     --nhMAC = "A0:36:9f:3b:6d:44",
--     nhMAC = "a0:36:9f:3b:5b:" .. string.format("%02x", i),
--     --nhIPv4 = "10.0.1.5",
--     networkIP = tostring(i) .. ".0.0.0",
--     --networkIP = tostring(i) .. "." .. tostring(j) .. "." .. tostring(k) .. ".0",
--     networkPrefix = 8
--   }
-- end

config.ports = ports
config.routes = routes

return config
