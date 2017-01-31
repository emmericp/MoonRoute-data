package.path = package.path .. ";" .. "/usr/share/lua/5.1/?.lua"
package.cpath = package.cpath .. ";" .. "/usr/lib/x86_64-linux-gnu/lua/5.1/?.so"
function script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end
package.path = package.path .. ";" .. script_path() .. "/?.lua"

local dpdk		= require "dpdk"
local device	= require "device"
local lpm     = require "lpm"
local distribute = require "distribute"
local l3arp = require "l3SyncArp"
local pipe = require "pipe"

local ui = require("userInterface")
local slowPath = require("slowPath")
local fastPath = require("fastPath")

function getNumber(table)
  local i = 0
  for _,_ in pairs(table) do
    i = i + 1
  end
  return i
end

--- Initializes the router
function master(...)
  dpdk.enablePowerManagement(0)
  dpdk.enablePowerManagement(1)
  dpdk.enablePowerManagement(2)
  dpdk.enablePowerManagement(3)
  dpdk.enablePowerManagement(4)
  dpdk.enablePowerManagement(5)
  dpdk.enablePowerManagement(6)
  dpdk.enablePowerManagement(7)
  dpdk.setCPUFreqMin(0)
  dpdk.setCPUFreqMin(1)
  dpdk.setCPUFreqMin(2)
  dpdk.setCPUFreqMin(3)
  dpdk.setCPUFreqMin(4)
  dpdk.setCPUFreqMin(5)
  dpdk.setCPUFreqMin(6)
  dpdk.setCPUFreqMin(7)
  for i = 1, 8 do
    dpdk.setCPUFreqUp(0)
    dpdk.setCPUFreqUp(1)
    dpdk.setCPUFreqUp(2)
    dpdk.setCPUFreqUp(3)
    dpdk.setCPUFreqUp(4)
    dpdk.setCPUFreqUp(5)
    dpdk.setCPUFreqUp(6)
    dpdk.setCPUFreqUp(7)
  end
  printf("power set")
  local config = dofile "/root/cfg.lua"
  -- we need to enable queues for each port:
  -- RX:
  --  - 1 ARP
  --  - 1 slow path
  --  - nRss fast path
  -- TX:
  --  - 1 ARP
  --  - 1 slow path
  --  - number of fast path cores
  --local count_fast_path_cores = 0
  --for _, port in pairs(config.ports) do
  --  if(port.direction == "inout" or port.direction == "in")then
  --    count_fast_path_cores = count_fast_path_cores + port.nRss
  --  end
  --end

  printfColor("Assigning devices to cores...", "yellow")
  for _, port in pairs(config.ports) do
    port["device"] = device.get(port.mac)
    if(port.device == nil) then
      errorf("ERROR: device with mac %s not found", port.mac)
    end
  end

  -- cores will contain a list of ports and queues for each cpu core
  local cores = {}
  config["nrPorts"] = 0
  local outputSeqNr = 0
  for _, port in pairs(config.ports) do
    config.nrPorts = config.nrPorts + 1
    if(port.direction == "inout" or port.direction == "out")then
      port["outputSeqNr"] = outputSeqNr
      outputSeqNr = outputSeqNr + 1
    end
    if(port.direction == "inout" or port.direction == "in")then
      port.fastPathCores = port.fastPathCores or config.fastPathCores
      --port.rxBurstSize = port.rxBurstSize or config.rxBurstSize
      local i = 0
      for _, c in ipairs(port.fastPathCores) do
        printf("core %d -> mac: %s", c, port.mac)
        cores[c] = cores[c] or {}
        cores[c]["ports"] = cores[c]["ports"] or {}
        cores[c]["ports"][getNumber(cores[c]["ports"])+1] = port
        -- every core gets one rx queue for each assigned port
        cores[c]["rxQueues"] = cores[c]["rxQueues"] or {}
        cores[c]["rxQueues"][getNumber(cores[c]["rxQueues"])+1] = port.device:getRxQueue(i)
        i = i + 1
      end
    end
  end

  -- configure the devices:
  printfColor("Configuring devices...", "yellow")
  for _, port in pairs(config.ports) do
    printf(" configuring %s", port.mac)
    port["direction"] = port["direction"] or "inout"
    if(port.direction == "out") then
      --device.config({port=port.device.id, rxQueues=0, txQueues=1+1+getnumber(cores)})
      errorf("out devices currently not supported")
    elseif(port.direction == "in") then
      errorf("in devices currently not supported")
      --device.config({port=port.device.id, rxQueues=1+1+getNumber(port.fastPathCores), txQueues=0, rssNQueues=getNumber(port.fastPathCores), separateMemPools=true, memPoolSize = 512*2})
    else
      device.config({
        port=port.device.id,
        rxQueues=1+1+getNumber(port.fastPathCores),
        txQueues=1+1+getNumber(cores),
        rssNQueues=getNumber(port.fastPathCores),
        --rxDescs = 512,
        rxDescs = 4*config.rxBurstSize,
        txDescs = 256,
        separateMemPools=false,
        memPoolSize = 2*512 * (1+1+getNumber(port.fastPathCores)) + config.nrPorts * config.txQueueSize + config.slowPathQueueSize + 1
        --memPoolSize = 2*512 + config.nrPorts * config.txQueueSize + config.slowPathQueueSize + 1
        --memPoolSize = 8*config.rxBurstSize + config.nrPorts * config.txQueueSize + config.slowPathQueueSize + 1
        --rxDescs = 2*config.rxBurstSize,
        --txDescs = 2*config.txQueueSize,
        --separateMemPools=true,
        --memPoolSize = 2*config.rxBurstSize + config.nrPorts * config.txQueueSize + config.slowPathQueueSize + 1
        })
    end
  end

  printfColor("Waiting for devices to come up...", "yellow")
  device.waitForLinks();

  printfColor("Initializing ARP...", "yellow")
  for _, port in pairs(config.ports) do
    port["arpRxQueue"] = port.device:getRxQueue(1+1+getNumber(port.fastPathCores) - 1)
    port["arpTxQueue"] = port.device:getTxQueue(1+1+getNumber(cores) - 1)
  end
  local arpInstance = l3arp.createSyncArp(config)
  config["arpInstance"] = arpInstance

  local lpmTable = lpm.createLpm4Table()
  printfColor("Configuring initial routes...", "yellow")
  lpmTable:addRoutesFromTable(config.routes, config.ports, function(ip) return config.arpInstance:blockingLookup(ip, 0.5) end)

  -- start fast path units
  printfColor("Starting Fast Path units...", "yellow")
  local i = 1
  for c, core in pairs(cores) do
    local distributor = distribute.createDistributor(nil, nil, config.nrPorts, false)
    --local distributor = distribute.createDistributor(nil, nil, config.nrPorts, true)
    -- register all output ports
    for _, port2 in pairs(config.ports) do
      if(port2.direction == "inout" or port2.direction == "out")then
        distributor:registerOutput(port2.outputSeqNr,
        port2.device:getTxQueue(i),
        port2.txQueueSize or config.txQueueSize,
        port2.txQueueTimeout or config.txQueueTimeout)
      end
    end
    -- create the queues for communicating with the slow path:
    local slowQueue = pipe.newFastCPipe({size = config.slowPathQueueSize})
    core["slowQueue"] = slowQueue
    local cmdRxQueue = pipe.newSlowPipe()
    core["cmdRxQueue"] = cmdRxQueue
    local cmdTxQueue = pipe.newSlowPipe()
    core["cmdTxQueue"] = cmdTxQueue
    -- TODO: NUMA awareness
    printf("  Launch FastPath on core %d...", c)
    local testports = {}
    if(c < 4) then
      testports = {config.ports["Port1"].device:getTxQueue(i) }
    else
      testports = {config.ports["Port2"].device:getTxQueue(i) }
    end
    --testports = {config.ports["Port2"].device:getTxQueue(i), config.ports["Port1"].device:getTxQueue(i) }

    dpdk.launchLuaOnCore(c, "runFastPath", lpmTable, distributor,
      core.rxQueues,
      slowQueue,
      cmdRxQueue,
      cmdTxQueue,
      config.rxBurstSize, c, testports )
    i = i+1
  end

  -- enable the telnet interface:
  config["dynamicRoutes"] = {}
  local telnetUi
  if(config.telnetEnable) then
    printfColor("Initializing telnet user interface...", "yellow")
    telnetUi = ui.createUserInterface(config)
  end

  -- start slow path unit
  printfColor("Initializing Slow Path for core 0...", "yellow")
  -- Now we set up the slow path:
  local distributor = distribute.createDistributor(nil, nil, config.nrPorts, false)
  -- register all output ports
  for _, port2 in pairs(config.ports) do
    if(port2.direction == "inout" or port2.direction == "out")then
      distributor:registerOutput(port2.outputSeqNr,
        port2.device:getTxQueue(1+1+getNumber(cores) - 1 - 1),
        port2.txQueueSize or config.txQueueSize,
        port2.txQueueTimeout or config.txQueueTimeout)
    end
  end
  local slowPathInstance = slowPath.createSlowPath(cores, config, lpmTable, distributor)


  printfColor("------------------", "green")
  printfColor(">> Router ready <<", "green")
  printfColor("------------------", "green")

  -- main loop on core 0:
  while dpdk.running() do
    if telnetUi then
      telnetUi:handle()
    end
    config.arpInstance:handle()
    slowPathInstance:handle()
  end

  dpdk.waitForSlaves()
end

function runFastPath(...)
  fastPath.run(...)
end
