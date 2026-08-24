local items = require "recipesched.items"
local recipes = require "recipesched.recipes"
local infra = require "recipesched.infra"
local storagegraph = require "recipesched.storagegraph"
local stockcheck = require "recipesched.stockcheck"
local nodechoice = require "recipesched.nodechoice"
local util = require "recipesched.util"
local os = require "os"
local math = require "math"

local FETCH_ALL = false

local function makePlanContext(name)
	return {
		nodesPresentCache = {},
		nodesNextItems = {},
		actionStack = {},
		stockDrivers = {},
		ingoingStockLists = {},
		ttl = 64,
		name = name,
	}
end

local function getPresentAmount(ctx, itemName, nodeName)
	local forNode = ctx.nodesPresentCache[nodeName]
	if not forNode then
		return 0
	end
	local entry = forNode[itemName]
	if not entry then
		return 0
	end
	return entry.amount or 0
end

local function getFreePresentAmount(ctx, itemName, nodeName)
	local present = getPresentAmount(ctx, itemName, nodeName)
	if present == 0 then
		return 0
	end
	local nextItems = ctx.nodesNextItems[nodeName]
	if nextItems then
		local wantAmount = nextItems[itemName] or 0
		if wantAmount > 0 then
			present = present - wantAmount
		end
	end
	if present < 0 then
		return 0
	end
	return present
end

local function clearNegativeDesires(ctx)
	local nodesNextItems = ctx.nodesNextItems
	for nodeName, nextItems in pairs(nodesNextItems) do
		for itemName, value in pairs(nextItems) do
			if value <= 0 then
				nextItems[itemName] = nil
			end
		end
		if not next(nextItems) then
			nodesNextItems[nodeName] = nil
		end
	end
end

local function wantItemAt(ctx, itemName, amount, nodeName)
	local nodesNextItems = ctx.nodesNextItems
	local nextItems = nodesNextItems[nodeName]
	if not nextItems then
		nextItems = {}
		nodesNextItems[nodeName] = nextItems
	end
	local value = nextItems[itemName] or 0
	value = value + amount
	if value == 0 then
		value = nil
	end
	nextItems[itemName] = value
	if not next(nextItems) then
		nodesNextItems[nodeName] = nil
	end
end

local function findRecipeFor(ctx, itemName)
	local candidates = recipes.recipesForResult(itemName)
	-- TODO can we use lower priority recipes under some conditions?
	return candidates[1]
end

local function updateIngoingStockListFor(ctx, sinkName)
	if ctx.ingoingStockLists[sinkName] then
		return
	end
	local lst = {}
	for nodeName in storagegraph.iterateIngoingPaths(sinkName) do
		local driver = stockcheck.getNodeDriver(nodeName)
		if driver then
			table.insert(lst, nodeName)
			ctx.stockDrivers[nodeName] = driver
		end
	end
	ctx.ingoingStockLists[sinkName] = lst
end

local function updatePresentCache(ctx)
	local nodesToFetch = {}
	local nodeNames = {}
	local itemSet = {}
	if FETCH_ALL then
		-- FIXME high memory usage
		for itemName in pairs(items.registry) do
			itemSet[itemName] = true
		end
	else
		for _, nextItems in pairs(ctx.nodesNextItems) do
			-- TODO add retries
			for itemName, wantAmount in pairs(nextItems) do
				if wantAmount > 0 then
					itemSet[itemName] = true
				end
			end
		end
	end
	for nodeName in pairs(ctx.stockDrivers) do
		local presentCache = ctx.nodesPresentCache[nodeName]
		if not presentCache then
			presentCache = {}
			ctx.nodesPresentCache[nodeName] = presentCache
		end
		local updated = false
		local toFetch = {}
		nodesToFetch[nodeName] = toFetch
		for itemName in pairs(itemSet) do
			if not presentCache[itemName] then
				table.insert(toFetch, itemName)
				updated = true
			end
		end
		if updated then
			table.insert(nodeNames, nodeName)
		end
	end
	util.runParallel(function(nodeName)
		local response = ctx.stockDrivers[nodeName].countPresentItems(nodesToFetch[nodeName])
		local presentCache = ctx.nodesPresentCache[nodeName]
		for itemName, entry in pairs(response) do
			presentCache[itemName] = entry
		end
	end, nodeNames)
end

local function makeDeliveryAction(srcName, dstName, itemName, deliverAmount)
	local steps = {}
	local nodesInputs = {}
	local nodesOutputs = {}
	local act = {
		steps = steps,
		nodesInputs = nodesInputs,
		nodesOutputs = nodesOutputs,
	}
	if srcName == dstName then
		return act
	end
	local pathStacks = {}
	local specList = items.nameToSpecList(itemName)
	for _, spec in ipairs(specList) do
		spec.size = deliverAmount
		table.insert(pathStacks, spec)
	end
	local _, path = storagegraph.findIngoingPath({[srcName] = true}, dstName, pathStacks)
	if not path then
		return nil
	end
	for _, edge in ipairs(path) do
		if not edge.auto then
			table.insert(steps, {"deliver", edge.from, edge.to, itemName, deliverAmount})
		end
	end
	nodesInputs[srcName] = {[itemName] = deliverAmount}
	nodesOutputs[dstName] = {[itemName] = deliverAmount}
	return act
end

local function makeRecipeDeliveryAction(ctx, nodeName, itemName, wantAmount)
	local recipeName = findRecipeFor(ctx, itemName)
	if not recipeName then
		return nil
	end
	local desc = recipes.registry[recipeName]
	local perSingle = recipes.recipeResultAmount(recipeName, itemName)
	if perSingle < 1 then
		error(("Bad recipe %q for %q"):format(recipeName, itemName))
	end
	local mult = math.ceil(wantAmount / perSingle)
	local choice = nodechoice.chooseNodesForRecipe(recipeName, nodeName)
	local outputEntry = choice.itemOutputs[itemName]
	if outputEntry.bad then
		error(("Bad recipe output node: %s"):format(outputEntry.msg))
	end
	local possibleNodes = outputEntry.nodes
	if #possibleNodes ~= 1 then
		error(("Bad recipe output node count: %d"):format(#possibleNodes))
	end

	local deliverySource = possibleNodes[1]
	local act = makeDeliveryAction(deliverySource, nodeName, itemName, wantAmount)
	if not act then
		return nil
	end
	table.insert(act.steps, 1, {"recipe", recipeName, nodeName, mult})
	local nodesInputs = act.nodesInputs
	local nodesOutputs = act.nodesOutputs
	do
		local value = 0
		local deliverySourceInputs = nodesInputs[deliverySource]
		if deliverySourceInputs then
			value = deliverySourceInputs[itemName]
			deliverySourceInputs[itemName] = nil
			if not next(deliverySourceInputs) then
				nodesInputs[deliverySource] = nil
			end
		end
		value = value - mult * outputEntry.amount
		if value < 0 then
			local deliverySourceOutputs = nodesOutputs[deliverySource]
			if not deliverySourceOutputs then
				deliverySourceOutputs = {}
				nodesOutputs[deliverySource] = deliverySourceOutputs
			end
			local oldValue = deliverySourceOutputs[itemName] or 0
			deliverySourceOutputs[itemName] = oldValue - value
		end
	end
	do
		local storageNodeName = choice.storageNodeName
		local storageNodeInputs = nodesInputs[storageNodeName]
		if not storageNodeInputs then
			storageNodeInputs = {}
			nodesInputs[storageNodeName] = storageNodeInputs
		end
		for inItemName, amount in pairs(desc.dependencies) do
			local value = storageNodeInputs[inItemName] or 0
			value = value + amount * mult
			storageNodeInputs[inItemName] = value
		end
	end
	if desc.skipDepsPresence then
		act.skipDepsPresence = true
	end
	return act
end

local function updateActionDelta(ctx, nodesDeltas, act)
	-- Subtract results
	for nodeName, outputs in pairs(act.nodesOutputs) do
		local deltas = nodesDeltas[nodeName]
		if not deltas then
			deltas = {}
			nodesDeltas[nodeName] = deltas
		end
		for itemName, amount in pairs(outputs) do
			local value = deltas[itemName] or 0
			value = value - amount
			deltas[itemName] = value
		end
	end
	-- Add dependencies
	for nodeName, inputs in pairs(act.nodesInputs) do
		local deltas = nodesDeltas[nodeName]
		if not deltas then
			deltas = {}
			nodesDeltas[nodeName] = deltas
		end
		for itemName, amount in pairs(inputs) do
			local value = deltas[itemName] or 0
			if act.skipDepsPresence then
				if not (ctx.nodesPresentCache[nodeName] or {})[itemName] then
					updatePresentCache(ctx)
				end
				local presentAmount = getPresentAmount(ctx, itemName, nodeName)
				local wantAmount = math.max(0, (ctx.nodesNextItems[nodeName] or {})[itemName] or 0)
				-- TODO: verify the validity of this formula
				local effectivePresentAmount = math.max(0, presentAmount - value - wantAmount)
				value = value + effectivePresentAmount
			end
			value = value + amount
			deltas[itemName] = value
		end
	end
end
local function addAction(addedActions, act)
	table.insert(addedActions.flows, act.steps)
end

local function stepPlan(ctx)
	if ctx.ttl < 1 then
		return false
	end
	ctx.ttl = ctx.ttl - 1
	local updated = false
	local stepNodeName = next(ctx.nodesNextItems)
	if not stepNodeName then
		return false
	end
	updateIngoingStockListFor(ctx, stepNodeName)
	updatePresentCache(ctx)
	local addedActions = {
		flows = {},
	}
	table.insert(ctx.actionStack, addedActions)
	local nodesDeltas = {}
	local deltas = {}
	nodesDeltas[stepNodeName] = deltas
	local nextItems = ctx.nodesNextItems[stepNodeName]
	for itemName, wantAmount in pairs(nextItems) do
		local negDelta = deltas[itemName]
		if negDelta and negDelta < 0 then
			wantAmount = wantAmount + negDelta
		end
		local presentCurrent = getPresentAmount(ctx, itemName, stepNodeName)
		wantAmount = wantAmount - presentCurrent
		if wantAmount > 0 then
			for _, precNodeName in ipairs(ctx.ingoingStockLists[stepNodeName]) do
				if wantAmount <= 0 then
					break
				end
				-- TODO check whether this particular item will not be intercepted on the path
				local availPrec = getFreePresentAmount(ctx, itemName, precNodeName)
				if availPrec > 0 then
					local deliverAmount = math.min(wantAmount, availPrec)
					local act = makeDeliveryAction(precNodeName, stepNodeName, itemName, deliverAmount)
					if act then
						addAction(addedActions, act)
						updateActionDelta(ctx, nodesDeltas, act)
						wantAmount = wantAmount - deliverAmount
						updated = true
					end
				end
			end
		end
		if wantAmount > 0 then
			local act = makeRecipeDeliveryAction(ctx, stepNodeName, itemName, wantAmount)
			if act then
				addAction(addedActions, act)
				updateActionDelta(ctx, nodesDeltas, act)
				updated = true
			end
		end
	end
	for nodeName, deltas in pairs(nodesDeltas) do
		for itemName, deltaValue in pairs(deltas) do
			-- FIXME future stages now can provide resources for past stages
			wantItemAt(ctx, itemName, deltaValue, nodeName)
		end
	end
	clearNegativeDesires(ctx)  -- is there a reason we were not doing this?
	return updated
end

local function finalizePlan(ctx)
	updatePresentCache(ctx)
	local missingItems = {}
	for nodeName, nextItems in pairs(ctx.nodesNextItems) do
		for itemName, wantAmount in pairs(nextItems) do
			wantAmount = wantAmount - getPresentAmount(ctx, itemName, nodeName)
			if wantAmount > 0 then
				table.insert(missingItems, {item = itemName, amount = wantAmount, node = nodeName})
			end
		end
	end
	local recipeQueue = {}
	for i = #ctx.actionStack, 1, -1 do
		local stage = ctx.actionStack[i]
		for _, flow in ipairs(stage.flows) do
			-- TODO consider task parallelization
			for _, step in ipairs(flow) do
				local kind = step[1]
				if kind == "recipe" then
					table.insert(recipeQueue, {recipe = step[2], node = step[3], amount = step[4]})
				elseif kind == "deliver" then
					table.insert(recipeQueue, {deliver = step[4], from = step[2], to = step[3], amount = step[5]})
				end
			end
		end
	end
	local plan = {
		missingItems = missingItems,
		recipeQueue = recipeQueue,
		name = ctx.name,
		context = ctx,
	}
	if #missingItems < 1 then
		plan.success = true
	else
		plan.success = false
		if ctx.ttl > 0 then
			plan.reason = "Missing items"
		else
			plan.reason = "Too deep"
		end
	end
	return plan
end

local function planForItem(itemName, amount, dstNode)
	amount = amount or 1
	dstNode = dstNode or infra.getDefaultStorageName()
	if not dstNode then
		error("No default storage node")
	end
	local ctx = makePlanContext(("Item %q * %d"):format(itemName, amount))
	wantItemAt(ctx, itemName, amount, dstNode)
	updatePresentCache(ctx)
	wantItemAt(ctx, itemName, getPresentAmount(ctx, itemName, dstNode), dstNode)
	while stepPlan(ctx) do
		os.sleep(0.05)
	end
	return finalizePlan(ctx)
end

return {
	planForItem = planForItem,
}
