local rpc = require "rpc"
local api = require "recipesched.api"

local RPC_PREFIX = "recipesched_"

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

return {
	registerRpc = registerRpc,
	unregisterRpc = unregisterRpc,
}
