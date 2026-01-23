local sides = require "sides"
local svcCrafting = require "craftersvc.robot.crafting"
local rpc = require "rpc"

local RPC_PREFIX = "robot_crafter_"

-- TODO: config loading
local ctx = {
	storageSide = sides.front,
}

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
	registerRpc = registerRpc,
	unregisterRpc = unregisterRpc,
	addServer = addServer,
	removeServer = removeServer,
}
