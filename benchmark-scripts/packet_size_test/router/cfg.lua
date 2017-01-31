-- run this config on cesis
config = {ports = {}, routes = {}}


-- GENERAL CONFIGURATION
config["txQueueSize"] = 128
config["txQueueTimeout"] = 0.001
config["rxBurstSize"] = 128
config["addRoutesToLocalNetworks"] = true
config["telnetEnable"] = true
config["telnetPort"] = 23
config["telnetBindIP"] = "0.0.0.0"
config["slowPathQueueSize"] = 64
config["distributorQueuesSize"] = 128


-- PORT CONFIGURATION
-- configuration, which applies to all ports
config["fastPathCores"] = {1}

-- port wise configuration
ports = {}

ports["Port1"] = {
  mac = "A0:36:9F:59:07:00",
  ipv4 = "10.0.2.1",
  ipv4Prefix = 24,
  direction = "inout",
  --fastPathCores = {1,2,3,4,5,6}
  --fastPathCores = {1,2,3}
}
ports["Port2"] = {
  --mac = "a0:36:9f:59:07:02",
  mac = "00:25:90:ED:BD:DD",
  ipv4 = "10.0.1.1",
  ipv4Prefix = 24,
  direction = "inout",
  --fastPathCores = {1,2,3,4,5,6}
  --fastPathCores = {4,5,6}
}


-- STATIC ROUTES CONFIGURATION
routes = {}

routes["Route1"] = {
  nhPort = "Port1",
  -- if a nhMAC field is present, it has priority over the nhIPv4 field
  nhMAC = "A0:36:9f:3b:6d:77",
  networkIP = "0.0.0.0",
  networkPrefix = 1
}
routes["Route2"] = {
  nhPort = "Port2",
  nhMAC = "A0:36:9f:3b:6d:77",
  networkIP = "128.0.0.0",
  networkPrefix = 1
}

config.ports = ports
config.routes = routes

return config
