require "routerUtils"
local socket = require "socket"

local router_userInterface = {}
mod.router_userInterface = router_userInterface
router_userInterface.__index = router_userInterface

local mod = {}

local cmds
function cmdsupdateRoutesfun(ui, clSocket, data)
  ui.config.forceLpmUpdate = true
  clSocket:send("Routing table update is beeing processed\n")
end

function cmdsaddRoutefun(ui, clSocket, data)
  local args = {}
  for i in data:gmatch("[^%s]+") do
    table.insert(args, i)
  end
  if(#args < 5) then
    clSocket:send("Not enough arguments.\n")
    return
  end
  local route = {
    nhPort = args[4],
    networkIP = args[2],
    networkPrefix = tonumber(args[3])
  }
  if(parseIP4Address(args[5])) then
    route["nhIPv4"] = args[5]
  else
    route["nhMAC"] = args[5]
  end
  local err = isRouteInvalid(route, ui.config)
  if(err) then
    clSocket:send("Invalid argument: " .. err .. "\n")
    return
  end
  table.insert(ui.routes, route)
  clSocket:send("Route to " .. getRouteString(route) .. " added successfully\n")
end
 
function cmdsshowRoutesfun(ui, clSocket, data)
  clSocket:send("Static routes:\n")
  for _, route in pairs(ui.config.routes) do
    clSocket:send(" " .. getRouteString(route) .. "\n")
  end
  clSocket:send("Dynamic routes:\n")
  for _, route in pairs(ui.routes) do
    clSocket:send(" " .. getRouteString(route) .. "\n")
  end
end

function cmdshelpfun(ui, clSocket, data)
  clSocket:send("Available commands:\n")
  for cmd, cmdt in pairs(cmds) do
    clSocket:send(" " .. cmd)
    if cmdt.aliases then
      clSocket:send(" (")
      for _, alias in pairs(cmdt.aliases) do
        clSocket:send(alias .. ", ")
      end
      clSocket:send(")")
    end
    clSocket:send(" :\t" .. (cmdt.help or "no help available") .. "\n")
  end
end

cmds = {
  help = {
    help = "Displays all available commands",
    fun = cmdshelpfun
  },
  addRoute = {
    aliases = {"ar"},
    help = "Arguments: networkIP networkPrefix nextHopPort [nextHopIP | nextHopMAC]. Adds a route entry to the dynamic routing table.",
    fun = cmdsaddRoutefun
  },
  updateRoutes = {
    aliases = {"ur"},
    help = "Forces an update oth the FastPath routing tables",
    fun = cmdsupdateRoutesfun
  },
  showRoutes = {
    aliases = {"sr"},
    help = "Shows all active routes",
    fun = cmdsshowRoutesfun
  }
}

function mod.createUserInterface(config)
  printf("Starting telnet interface at port %d", config.telnetPort or 23)
  local uiServer = socket.bind(config.telnetBindIP or "0.0.0.0", config.telnetPort or 23)
  if(not uiServer) then
    errorf("ERROR: can not create telnet server socket")
  end
  local aliasedCmds = {}
  for cmdname, cmd in pairs(cmds) do
    aliasedCmds[cmdname] = cmd
    -- allpy all aliases
    if cmd.aliases then
      for _, alias in pairs(cmd.aliases) do
        aliasedCmds[alias] = cmd
      end
    end

  end

  config["forceLpmUpdate"] = false
  return setmetatable({
    cmds = aliasedCmds,
    config = config,
    routes = config.dynamicRoutes,
    uiServer = uiServer,
    uiClients = {},
  }, router_userInterface)
end

function router_userInterface:handle()
    if(self.uiServer) then
      self.uiServer:settimeout(0)
      local clSocket = self.uiServer:accept()
      if(clSocket)then
        clIp, clPort = clSocket:getpeername()
        printf("Client connected from %s:%d", clIp, clPort)
        clSocket:settimeout(0)
        clSocket:send("Welcome!\n% ")
        table.insert(self.uiClients, clSocket)
      end
      self:handleClients()
    end
end

function router_userInterface:handleClients()
  for i, socket in pairs(self.uiClients) do
    local data, err = socket:receive()
    if err == "closed" or data == "quit" then
      clIp, clPort = socket:getpeername()
      printf("Client disconnected (was %s:%d)", clIp, clPort)
      socket:close()
      table.remove(self.uiClients, i)
      break
    end
    if not err then
      local cmd = (function()
        for i in data:gmatch("%w+") do
          return i
        end
        end)()
      cmd = self.cmds[cmd]
      if(cmd) then
        cmd.fun(self, socket, data)
      else
        socket:send("Command not found :(\n")
      end
    socket:send("% ")
    end
  end
end

return mod
