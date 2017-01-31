
config["txQueueTimeout"] = 0.001
config["addRoutesToLocalNetworks"] = true
config["telnetEnable"] = true
config["telnetPort"] = 23
config["telnetBindIP"] = "0.0.0.0"
config["slowPathQueueSize"] = 64
config["distributorQueuesSize"] = 128 -- FIXME:is this option used at all?


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

config.ports = ports
config.routes = routes

return config
