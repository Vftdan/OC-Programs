local lazytable = require "recipesched.lazytable"
local infra = require "recipesched.infra"
local storagegraph = require "recipesched.storagegraph"
local items = require "recipesched.items"
local recipes = require "recipesched.recipes"
local drivers = require "recipesched.drivers"

local validForVersion = 0
-- default node name -> recipe description -> solution
local cache

local function resetCache()
	cache = lazytable.create(function()
		return setmetatable({}, {__mode = "k"})
	end)
end
resetCache()

local function checkStateVersion()
	local lastVersion = infra.getStateVersion()
	if validForVersion ~= lastVersion then
		resetCache()
	end
end

local function followPossibleItemOutputs(startNodeName, itemName, amount)
	local specList = items.nameToSpecList(itemName)
	for _, spec in ipairs(specList) do
		spec.size = amount
		local stableNodeName, msg = infra.stackFollowAutoOut(startNodeName, spec)
		if stableNodeName == nil then
			return nil, msg
		end
		stableSet[stableNodeName] = true
	end
	local stableList = {}
	for k in pairs(stableSet) do
		table.insert(stableList, k)
	end
	table.sort(stableList)
	return stableList
end

local function chooseUncached(defaultNodeName, recipeName, desc)
	local driverFeatureServers = {}
	local itemOutputs = {}
	local result = {
		driverFeatureServers = driverFeatureServers,
		node = nil,
		storageNodeName = nil,
		itemOutputs = itemOutputs,
	}
	local destNodeName = desc.nodeName
	local reqFeatureList = desc.driverFeatures
	local outStartNodeName
	if destNodeName then
		outStartNodeName = destNodeName
		local destNode = infra.nodeRegistry[destNodeName]
		if not destNode then
			error(("Recipe %q bound to a non-existent node %q"):format(recipeName, destNodeName))
		end
		local srvDescr = destNode.inputServer
		if not srvDescr then
			error(("Recipe %q bound to a node %q without an input server"):format(recipeName, destNodeName))
		end
		if not drivers.hasAllFeatures(srvDescr.driver, reqFeatureList) then
			error(("Recipe %q bound to a node %q with an input server not implementing the required driver features"):format(recipeName, destNodeName))
		end
		for _, feature in ipairs(reqFeatureList) do
			driverFeatureServers[feature] = srvDescr
		end
		result.node = destNode
		result.storageNodeName = srvDescr.storage
	else
		if not storagegraph.isStorageNode(defaultNodeName) then
			error(("Default node %q is not a storage node"):format(defaultNodeName))
		end
		local stacks = {}
		for _, resultEntry in ipairs(desc.results) do
			local itemName = recipes.getRecipeItemName(resultEntry.item)
			if not itemName then
				error(("Not an item: %q"):format(resultEntry.item))
			end
			local specList = items.nameToSpecList(itemName)
			for _, spec in ipairs(specList) do
				spec.size = resultEntry.amount  -- Warning: we only set the value for a single recipe invocation
				table.insert(stacks, spec)
			end
		end
		local foundStoNodeName = nil
		local stoNode
		local driverNames
		for stoNodeName in storagegraph.iterateIngoingPaths(defaultNodeName, stacks) do
			stoNode = infra.nodeRegistry[stoNodeName]
			if not stoNode then
				error(("Iterating through a non-existent node %q"):format(stoNodeName))
			end
			driverNames = {}
			for driverName, serverList in pairs(stoNode.servedDrivers) do
				if #serverList > 0 then
					table.insert(driverNames, driverName)
				end
			end
			if drivers.togetherHaveAllFeatures(reqFeatureList, driverNames) then
				foundStoNodeName = stoNodeName
				break
			end
		end
		if not foundStoNodeName then
			error(("No reachable node implementing all features for the recipe %q"):format(recipeName))
		end
		result.storageNodeName = foundStoNodeName
		outStartNodeName = foundStoNodeName
		table.sort(driverNames)
		for _, feature in ipairs(reqFeatureList) do
			local driverName = assert(drivers.getDriverNamesWithFeature(feature, driverNames)[1])
			local srvDescr = assert(stoNode.servedDrivers[driverName][1])
			driverFeatureServers[feature] = srvDescr
		end
	end

	for _, resultEntry in ipairs(desc.results) do
		local itemName = recipes.getRecipeItemName(resultEntry.item)
		if not itemName then
			error(("Not an item: %q"):format(resultEntry.item))
		end
		local outputEntry = itemOutputs[itemName] or {amount = 0}
		outputEntry.amount = outputEntry.amount + resultEntry.amount
		itemOutputs[itemName] = outputEntry
	end
	for itemName, outputEntry in pairs(itemOutputs) do
		local bad = false
		local badMsg
		local stableSet = {}
		local specList = items.nameToSpecList(itemName)
		for _, spec in ipairs(specList) do
			spec.size = outputEntry.amount  -- Warning: we only set the value for a single recipe invocation
			local stableNodeName, msg = infra.stackFollowAutoOut(outStartNodeName, spec)
			if stableNodeName == nil then
				bad = true
				badMsg = msg
				break
			end
			stableSet[stableNodeName] = true
		end
		if bad then
			outputEntry.bad = true
			outputEntry.msg = badMsg
		else
			local stableList = {}
			for k in pairs(stableSet) do
				table.insert(stableList, k)
			end
			table.sort(stableList)
			outputEntry.nodes = stableList
		end
	end

	return result
end

local function chooseNodesForRecipe(recipeName, defaultNodeName)
	local desc = recipes.registry[recipeName]
	if not desc then
		error(("No such recipe: %q"):format(recipeName))
	end
	if not defaultNodeName then
		defaultNodeName = infra.getDefaultStorageName()
		if not defaultNodeName then
			error("No storage node is configured as default")
		end
	end
	local perNodeCache = cache[defaultNodeName]
	local result = perNodeCache[desc]
	if result then
		return result
	end
	result = chooseUncached(defaultNodeName, recipeName, desc)
	perNodeCache[desc] = result
	return result
end

return {
	followPossibleItemOutputs = followPossibleItemOutputs,
	chooseNodesForRecipe = chooseNodesForRecipe,
	resetCache = resetCache,
}
