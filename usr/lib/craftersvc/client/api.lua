local config = require "craftersvc.common.config"
local rpc = require "rpc"

local RPC_PREFIX = "craftersvc_"
local CFG_FILE = "/etc/craftersvc/client.cfg"

local cfg

local function loadConfig()
	cfg = config.readConfig(CFG_FILE, true) or {}
end

local function saveConfig()
	config.writeConfig(CFG_FILE, cfg)
end

loadConfig()

local function getServerName()
	return cfg.server
end

local function setServerName(hostname)
	cfg.server = hostname
end

local function callApi(method, ...)
	local hostname = getServerName() or error("craftersvc server name is not set")
	return rpc.call(hostname, RPC_PREFIX .. method, ...)
end

local function craftGrid(grid, amount)
	return callApi("craftGrid", grid, amount)
end

local function countItems(specList, opts)
	return callApi("countItems", specList, opts)
end

return {
	loadConfig = loadConfig,
	saveConfig = saveConfig,
	getServerName = getServerName,
	setServerName = setServerName,
	callApi = callApi,
	craftGrid = craftGrid,
	countItems = countItems,
}
