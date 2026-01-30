local robotPool = require "craftersvc.server.robotPool"
local search = require "craftersvc.server.search"
local config = require "craftersvc.common.config"
local rpc = require "rpc"
local os = require "os"

local RPC_PREFIX = "craftersvc_"
local CFG_FILE = "/etc/craftersvc/server.cfg"
local MAX_REPLAN_RETRIES = 8

local cfg

local strategies = {
	direct = function(grid, amount)
		return robotPool.withRobot(function(hostname)
			return rpc.call(hostname, "robot_crafter_craftGrid", grid, amount)
		end, true)
	end,
	planned = function(grid, amount)
		local transposer, side = search.getTransposer(cfg)
		for _ = 0, MAX_REPLAN_RETRIES do  -- retry in case validation fails
			local plan = search.planForGrid(transposer, side, grid, amount)
			if not plan then
				return 0
			end
			local result = robotPool.withRobot(function(hostname)
				return rpc.call(hostname, "robot_crafter_craftFromPlan", plan, {validateGrid = grid})
			end, true)
			if result ~= "INVALID" then
				return result
			end
			os.sleep(0.05)
		end
		error("Transposer-robot inventory mismatch or race condition")
	end,
}

local api = {
	craftGrid = function(grid, amount)
		local currentStrategy = strategies[config.get(cfg, {"strategy"}) or "direct"] or strategies.direct
		local result = 0
		while amount > 64 do
			result = result + currentStrategy(grid, 64)
			amount = amount - 64
			os.sleep(0.2)
		end
		return result + currentStrategy(grid, amount)
	end,
	countItems = function(specList, opts)
		local transposer, side = search.getTransposer(cfg)
		return search.countItems(transposer, side, specList, opts or {})
	end,
}

local function registerRpc()
	for k, v in pairs(api) do
		local qualified = RPC_PREFIX .. k
		rpc.register(qualified, v)
	end
end

local function unregisterRpc()
	for method in pairs(api) do
		local qualified = RPC_PREFIX .. method
		rpc.unregister(qualified)
	end
end

local function loadConfig()
	cfg = config.readConfig(CFG_FILE, true) or {}
	local strategy = config.get(cfg, {"strategy"})
	if type(strategy) ~= "string" or not strategies[strategy] then
		config.put(cfg, {"strategy"}, "direct")
	end
end

local function saveConfig()
	config.writeConfig(CFG_FILE, cfg)
end

loadConfig()

local function listStrategies()
	local result = {}
	for name in pairs(strategies) do
		table.insert(result, name)
	end
	return result
end

local function useStrategy(name)
	if not strategies[name] then
		error("Unknown strategy: " .. tostring(name))
	end
	cfg.strategy = name
end

return {
	registerRpc = registerRpc,
	unregisterRpc = unregisterRpc,
	loadConfig = loadConfig,
	saveConfig = saveConfig,
	listStrategies = listStrategies,
	useStrategy = useStrategy,
}
