local configloader = require "recipesched.configloader"
local apinames = require "recipesched.apinames"
local rpc = require "rpc"

local RPC_PREFIX = "recipesched_"

local function getRawApi()
	local cfg = configloader.loadNamed("client", {mustExist = true}).globals
	if cfg.useLocal then
		return require "recipesched.api"
	end
	local server = cfg.server
	if server then
		local api = {}
		for name, desc in pairs(apinames) do
			api[name] = function(...)
				return rpc.call(server, RPC_PREFIX .. name, ...)
			end
		end
		return api
	end
	error("Incomplete recipesched client config: `server` or `useLocal` must be assigned")
end

local function getApi()
	local rawApi = getRawApi()
	local api = {}
	for name, desc in pairs(apinames) do
		local module, method = desc[1], desc[2]
		local moduleTable = api[module]
		if not moduleTable then
			moduleTable = {}
			api[module] = moduleTable
		end
		moduleTable[method] = rawApi[name]
	end
	return api
end

return {
	getRawApi = getRawApi,
	getApi = getApi,
}
