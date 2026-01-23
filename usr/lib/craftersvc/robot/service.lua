local sides = require "sides"
local svcCrafting = require "craftersvc.robot.crafting"
local rpc = require "rpc"
local config = require "craftersvc.common.config"

local RPC_PREFIX = "robot_crafter_"
local CTX_FILE = "/etc/craftersvc/robot.cfg"

local ctx

local api = {
	craftGrid = function(grid, amount)
		svcCrafting.clearInventory(ctx)
		local result = table.pack(pcall(svcCrafting.craftGrid, ctx, grid, amount))
		svcCrafting.clearInventory(ctx)
		if result[1] then
			return table.unpack(result, 2, result.n)
		else
			error(table.unpack(result, 2, result.n))
		end
	end,
	craftFromPlan = function(plan)
		svcCrafting.clearInventory(ctx)
		local result = table.pack(pcall(svcCrafting.craftFromPlan, ctx, plan))
		svcCrafting.clearInventory(ctx)
		if result[1] then
			return table.unpack(result, 2, result.n)
		else
			error(table.unpack(result, 2, result.n))
		end
	end,
}

local function loadConfig()
	ctx = config.readConfig(CTX_FILE, true) or {}
	if type(config.get(ctx, {"storageSide"})) ~= "number" then
		config.put(ctx, {"storageSide"}, sides.front)
	end
end

local function saveConfig()
	config.writeConfig(CTX_FILE, ctx)
end

loadConfig()

local function registerRpc()
	for k, v in pairs(api) do
		local qualified = RPC_PREFIX .. k
		-- Robot service is private
		rpc.allow[qualified] = rpc.allow[qualified] or {}
		rpc.register(qualified, v)
	end
end

local function unregisterRpc()
	for method in pairs(api) do
		local qualified = RPC_PREFIX .. method
		rpc.unregister(qualified)
	end
end

local function addServer(hostname)
	for method in pairs(api) do
		rpc.allow(RPC_PREFIX .. method, hostname)
	end
end

local function removeServer(hostname)
	for method in pairs(api) do
		local qualified = RPC_PREFIX .. method
		if not rpc.allow[qualified] then
			rpc.allow[qualified] = {}
		end
		rpc.allow[qualified][hostname] = nil
	end
end

return {
	loadConfig = loadConfig,
	saveConfig = saveConfig,
	registerRpc = registerRpc,
	unregisterRpc = unregisterRpc,
	addServer = addServer,
	removeServer = removeServer,
}
