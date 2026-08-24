local configloader = require "recipesched.configloader"
local lazytable = require "recipesched.lazytable"
local util = require "recipesched.util"

local defaultStorageName = nil
local stateVersion = 0
local nodeRegistry = {}
local driverStoragesRegistry = {}

local serverRefs, serverAccessor, storageServers
local function clearLoadServerRegistry()
	serverRefs = setmetatable({}, {__mode = "k"})
	-- storage -> driver name -> driver -> true
	storageServers = lazytable.create(function() return lazytable.create(function() return {} end, {weak = true, iterable = true}) end, {iterable = true})
end
clearLoadServerRegistry()
serverAccessor = lazytable.create(function(name)
	if type(name) ~= "string" then
		error("Non-string server reference")
	end
	local repr = "server." .. name
	return lazytable.create(function(key)
		if key == "name" then
			return name
		end
	end, {frozen = true, toString = function() return repr end})
end, {
	call = function(descr)
		if type(descr) ~= "table" then
			error("Non-table `server` options")
		end
		local name = descr.name or descr.host
		if type(name) ~= "string" then
			error("No name for the server")
		end
		serverAccessor[name] = descr
		return serverAccessor[name]
	end,
	beforeSet = function(name, value)
		if type(value) ~= "table" then
			error("server." .. name .. ": table expected, got " .. type(value))
		end
		local symb = serverAccessor[name]
		local descr = serverRefs[symb]
		if descr ~= nil then
			serverRefs[symb] = descr
			return nil, nil
		end
		descr = {name = name}
		local driver = value.driver
		if type(driver) ~= "string" then
			error("server." .. name .. ".driver: string expected, got " .. type(driver))
		end
		descr.driver = driver
		local host = value.host
		if type(host) ~= "string" then
			error("server." .. name .. ".host: string expected, got " .. type(host))
		end
		descr.host = host
		for k, v in pairs(value) do
			descr[k] = v
		end
		if type(descr.name) ~= "string" then
			error("server." .. name .. ".name: string or nil expected, got " .. type(descr.name))
		end
		descr.storage = nil
		local storage = value.storage
		if type(storage) ~= "nil" then
			if type(storage) ~= "table" then
				error("server." .. name .. ".storage: table or nil expected, got " .. type(storage))
			end
			descr.storage = storage
			storageServers[storage][driver][descr] = true
		end
		serverRefs[symb] = descr
		return nil, nil
	end,
})

local nodeRefs
local function clearLoadNodeRegistry()
	nodeRefs = setmetatable({}, {__mode = "k"})
end
local function wrapNodeDescr(descr)
	local symb = {}
	nodeRefs[symb] = descr
	return symb
end
clearLoadNodeRegistry()

local IMPLICIT = lazytable.symbol("IMPLICIT")
local EMPTY_SPEC = {}

local loadImports = {
	server = serverAccessor,
	warehouse = function(inDescr)
		local outDescr = {}
		outDescr.isDefaultStorage = not not inDescr.default
		outDescr.isProcessor = false
		outDescr.autoOut = {}
		return wrapNodeDescr(outDescr)
	end,
	machine_input = function(inDescr)
		local outDescr = {}
		outDescr.isDefaultStorage = false
		outDescr.isProcessor = true  -- do not expect to be able to extract the same items as the inputed ones
		local srvSymb = inDescr.server
		if type(srvSymb) ~= "table" then
			error("Non-table `server` reference")
		end
		outDescr.inSrvRef = srvSymb
		local localName = inDescr.name
		if type(localName) ~= "string" then
			error("Non-string `name` field")
		end
		local inputCost = inDescr.cost
		if inputCost ~= nil and (type(inputCost) ~= "number" or inputCost < 0) then
			error("Not a non-negative `cost` field")
		end
		outDescr.inputCost = inputCost or 10  -- TODO
		outDescr.localName = localName
		local outName = inDescr.output
		if outName ~= nil and type(outName) ~= "string" then
			error("Non-string `output` field")
		end
		outDescr.autoOut = {
			{EMPTY_SPEC, outName or IMPLICIT, 0},
		}
		return wrapNodeDescr(outDescr)
	end,
	channel = function(inDescr)
		local outDescr = {}
		outDescr.isDefaultStorage = false
		outDescr.isProcessor = false
		local srvSymb = inDescr.server
		if type(srvSymb) ~= "table" then
			error("Non-table `server` reference")
		end
		outDescr.inSrvRef = srvSymb
		local inputCost = inDescr.cost
		if inputCost ~= nil and (type(inputCost) ~= "number" or inputCost < 0) then
			error("Not a non-negative `cost` field")
		end
		outDescr.inputCost = inputCost or 10
		local localName = inDescr.name
		if type(localName) ~= "string" then
			error("Non-string `name` field")
		end
		outDescr.localName = localName
		local outName = inDescr.output
		if type(outName) ~= "string" then
			error("Non-string `output` field")
		end
		outDescr.autoOut = {
			{EMPTY_SPEC, outName, 0},
		}
		return wrapNodeDescr(outDescr)
	end,
}

local function reload()
	clearLoadServerRegistry()
	clearLoadNodeRegistry()
	local loaded = configloader.loadNamed("infra", {imports = loadImports})
	if not loaded then
		return false
	end
	local newNodeRegistry = {}
	local newDriverStoragesRegistry = {}
	local newDefaultStorageName = nil
	local refToName = {}
	for k, nodeRef in pairs(loaded.globals) do
		if type(nodeRef) ~= "table" then
			error("Non-table value: " .. k)
		end
		local nodeDescr = nodeRefs[nodeRef]
		if not nodeDescr then
			error("Not a node: " .. k)
		end
		refToName[nodeRef] = k
		local inSrvDescr = nil
		do
			local srvSymb = nodeDescr.inSrvRef
			if srvSymb then
				inSrvDescr = serverRefs[srvSymb]
				if inSrvDescr == nil then
					error("Non-server `server` reference")
				end
			end
		end
		local ownServersLazy = storageServers[nodeRef]
		local servedDrivers = {}
		for driverName, srvSet in pairs(ownServersLazy) do
			local srvList = {}
			for srvDescr in pairs(srvSet) do
				table.insert(srvList, srvDescr)
			end
			servedDrivers[driverName] = srvList
			local driverStorages = newDriverStoragesRegistry[driverName]
			if not driverStorages then
				driverStorages = {}
				newDriverStoragesRegistry[driverName] = driverStorages
			end
			driverStorages[k] = true
		end
		if nodeDescr.isDefaultStorage then
			newDefaultStorageName = k
		end
		newNodeRegistry[k] = {
			registryName = k,
			inputServer = inSrvDescr,
			servedDrivers = servedDrivers,
			isDefaultStorage = nodeDescr.isDefaultStorage,
			isProcessor = nodeDescr.isProcessor,
			autoOut = nodeDescr.autoOut,
			localName = nodeDescr.localName,
			inputCost = nodeDescr.inputCost,
		}
	end
	for _, srvDescr in pairs(serverRefs) do
		local nodeRef = srvDescr.storage
		if nodeRef then
			local nodeKey = assert(refToName[nodeRef])
			srvDescr.storage = nodeKey
		end
	end
	for k, v in pairs(newNodeRegistry) do
		local autoOut = v.autoOut
		for _, route in ipairs(autoOut) do
			local nextKey = route[2]
			if nextKey == IMPLICIT then
				local inSrvDescr = assert(v.inputServer)
				nextKey = assert(inSrvDescr.storage)
				route[2] = nextKey
			end
			assert(type(nextKey) == "string")
			if not newNodeRegistry[nextKey] then
				error(("Invalid auto output node %q of %q"):format(k, nextKey))
			end
		end
	end
	stateVersion = stateVersion + 1
	for k in pairs(nodeRegistry) do
		nodeRegistry[k] = nil
	end
	for k, v in pairs(newNodeRegistry) do
		nodeRegistry[k] = v
	end
	for k in pairs(driverStoragesRegistry) do
		driverStoragesRegistry[k] = nil
	end
	for k, v in pairs(newDriverStoragesRegistry) do
		driverStoragesRegistry[k] = v
	end
	defaultStorageName = newDefaultStorageName
	return true
end

local function getStateVersion()
	return stateVersion
end

local function getDefaultStorageName()
	return defaultStorageName
end

-- Network API wrappers
local function getNodeRegistryElement(key)
	return nodeRegistry[key]
end

local function getNodeRegistryKeys()
	local result = {}
	for key in pairs(nodeRegistry) do
		table.insert(result, key)
	end
	table.sort(result)
	return result
end

local function getDriverNames()
	local result = {}
	for key in pairs(driverStoragesRegistry) do
		table.insert(result, key)
	end
	table.sort(result)
	return result
end

local function getDriverStorages(driverName)
	local result = {}
	local storageSet = driverStoragesRegistry[driverName]
	if not storageSet then
		return result
	end
	for key in pairs(storageSet) do
		table.insert(result, key)
	end
	table.sort(result)
	return result
end

local function getNodeDriverNames(nodeName)
	local node = nodeRegistry[nodeName]
	if not node then
		error(("Not a node: %q"):format(nodeName))
	end
	local driverNames = {}
	for driverName, serverList in pairs(node.servedDrivers) do
		if #serverList > 0 then
			table.insert(driverNames, driverName)
		end
	end
	table.sort(driverNames)
	return driverNames
end

local function stackFollowAutoOut(nodeName, stack)
	local visited = {}
	local nextNodeName
	while true do
		nextNodeName = nil
		visited[nodeName] = true
		local node = nodeRegistry[nodeName]
		local routes = node.autoOut
		if #routes == 0 then
			return nodeName
		end
		for _, route in ipairs(routes) do
			if util.matchItemSpec(stack, route[1]) then
				nextNodeName = route[2]
				if nextNodeName == nodeName then
					return nodeName
				end
				break
			end
		end
		if not nextNodeName then
			return nodeName
		end
		if visited[nextNodeName] then
			return nil, "cyclic auto-output"
		end
		nodeName = nextNodeName
	end
end

return {
	nodeRegistry = nodeRegistry,
	driverStoragesRegistry = driverStoragesRegistry,
	reload = reload,
	getStateVersion = getStateVersion,
	getDefaultStorageName = getDefaultStorageName,
	getNodeRegistryElement = getNodeRegistryElement,
	getNodeRegistryKeys = getNodeRegistryKeys,
	getDriverNames = getDriverNames,
	getDriverStorages = getDriverStorages,
	getNodeDriverNames = getNodeDriverNames,
	stackFollowAutoOut = stackFollowAutoOut,
}
