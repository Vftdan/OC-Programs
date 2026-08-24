local infra = require "recipesched.infra"
local drivers = require "recipesched.drivers"
local thread = require "thread"

local driverCache = setmetatable({}, {__mode = "k"})

local function getNodeServer(nodeName)
	local driverNames = infra.getNodeDriverNames(nodeName)
	local driverName = drivers.getDriverNamesWithFeature("stockCount", driverNames)[1]
	if not driverName then
		return nil
	end
	local node = infra.nodeRegistry[nodeName]
	return assert(node.servedDrivers[driverName][1])
end

local function getNodeDriver(nodeName)
	local node = infra.nodeRegistry[nodeName]
	if not node then
		error(("Not a node: %q"):format(nodeName))
	end
	local driver = driverCache[node]
	if driver ~= nil then
		if not driver then
			return nil
		end
		return driver
	end
	local srvDescr = getNodeServer(nodeName)
	if not srvDescr then
		driverCache[node] = false
		return nil
	end
	local hostName = srvDescr.host
	local driverName = srvDescr.driver
	driver = drivers.loadForHost(driverName, hostName)
	driverCache[node] = driver
	return driver
end

local function combinedDriverCounter(driverList)
	return function(names)
		local innerResults = {}
		local err = nil
		local function f(driver)
			local success, reply = pcall(driver.countPresentItems, names)
			if success then
				innerResults[driver] = reply
			else
				err = reply or "driver.countPresentItems error"
			end
		end
		local threads = {}
		for _, d in ipairs(driverList) do
			table.insert(threads, thread.create(f, d))
		end
		thread.waitForAll(threads)
		if err then
			error(err)
		end
		local result = {}
		for _, name in ipairs(names) do
			local amount = 0
			for _, part in pairs(innerResults) do
				amount = amount + part[name].amount
			end
			result[name] = {amount = amount}
		end
	end
end

local function combinedNodeCounter(nodeNames)
	local driverList = {}
	for _, nodeName in ipairs(nodeNames) do
		local driver = getNodeDriver(nodeName)
		if not driver then
			return nil
		end
		table.insert(driverList, driver)
	end
	return combinedDriverCounter(driverList)
end

return {
	getNodeServer = getNodeServer,
	getNodeDriver = getNodeDriver,
	combinedDriverCounter = combinedDriverCounter,
	combinedNodeCounter = combinedNodeCounter,
}
