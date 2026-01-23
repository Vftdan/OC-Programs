local robotPool = require "craftersvc.server.robotPool"
local search = require "craftersvc.server.search"
local rpc = require "rpc"
local os = require "os"

local RPC_PREFIX = "craftersvc_"

local strategies = {
	direct = function(grid, amount)
		return robotPool.withRobot(function(hostname)
			return rpc.call(hostname, "robot_crafter_craftGrid", grid, amount)
		end, true)
	end,
	planned = function(grid, amount)
		local transposer, side = search.getTransposer()
		local plan = search.planForGrid(transposer, side, grid, amount)
		return robotPool.withRobot(function(hostname)
			return rpc.call(hostname, "robot_crafter_craftFromPlan", plan)
		end, true)
	end,
}

local currentStrategy = strategies.direct

local api = {
	craftGrid = function(grid, amount)
		local result = 0
		while amount > 64 do
			result = result + currentStrategy(grid, 64)
			amount = amount - 64
			os.sleep(0.2)
		end
		return result + currentStrategy(grid, amount)
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

local function listStrategies()
	local result = {}
	for name in pairs(strategies) do
		table.insert(result, name)
	end
	return result
end

local function useStrategy(name)
	local strategy = strategies[name]
	if not strategy then
		error("Unknown strategy: " .. tostring(name))
	end
	currentStrategy = strategy
end

return {
	registerRpc = registerRpc,
	unregisterRpc = unregisterRpc,
	listStrategies = listStrategies,
	useStrategy = useStrategy,
}
