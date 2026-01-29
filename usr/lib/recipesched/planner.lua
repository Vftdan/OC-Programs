local items = require "recipesched.items"
local recipes = require "recipesched.recipes"
local craftersvc = require "recipesched.driver.craftersvc"
local os = require "os"
local math = require "math"

local function makePlanContext(name)
	return {
		presentCache = {},
		nextItems = {},
		recipeStack = {},
		ttl = 64,
		name = name,
	}
end

local function wantItem(ctx, itemName, amount)
	local nextItems = ctx.nextItems
	local value = nextItems[itemName] or 0
	value = value + amount
	if value == 0 then
		value = nil
	end
	nextItems[itemName] = value
end

local function findRecipeFor(ctx, itemName)
	local candidates = recipes.recipesForResult(itemName)
	-- TODO can we use lower priority recipes under some conditions?
	return candidates[1]
end

local function updateDelta(deltas, desc, mult)
	-- Subtract results
	for _, entry in ipairs(desc.results) do
		local ref = entry.item
		local itemName = recipes.getRecipeItemName(ref)
		local value = deltas[itemName] or 0
		value = value - entry.amount * mult
		deltas[itemName] = value
	end
	-- Add dependencies
	for itemName, amount in pairs(desc.dependencies) do
		local value = deltas[itemName] or 0
		value = value + amount * mult
		deltas[itemName] = value
	end
end

local function updatePresentCache(ctx)
	local toFetch = {}
	for itemName, wantAmount in pairs(ctx.nextItems) do
		if wantAmount > 0 then
			if not ctx.presentCache[itemName] then
				table.insert(toFetch, itemName)
			end
		end
	end
	local response = craftersvc.countPresentItems(toFetch)
	for itemName, entry in pairs(response) do
		ctx.presentCache[itemName] = entry
	end
end

local function stepPlan(ctx)
	if ctx.ttl < 1 then
		return false
	end
	updatePresentCache(ctx)
	ctx.ttl = ctx.ttl - 1
	local addedRecipes = {}
	local deltas = {}
	table.insert(ctx.recipeStack, addedRecipes)
	local updated = false
	for itemName, wantAmount in pairs(ctx.nextItems) do
		local negDelta = deltas[itemName]
		if negDelta and negDelta < 0 then
			wantAmount = wantAmount + negDelta
		end
		wantAmount = wantAmount - ctx.presentCache[itemName].amount
		if wantAmount > 0 then
			local recipeName = findRecipeFor(ctx, itemName)
			if recipeName then
				local desc = recipes.registry[recipeName]
				local perSingle = recipes.recipeResultAmount(recipeName, itemName)
				if perSingle < 1 then
					error(("Bad recipe %q for %q"):format(recipeName, itemName))
				end
				local mult = math.ceil(wantAmount / perSingle)
				updateDelta(deltas, desc, mult)
				addedRecipes[recipeName] = (addedRecipes[recipeName] or 0) + mult
				updated = true
			end
		end
	end
	for itemName, deltaValue in pairs(deltas) do
		wantItem(ctx, itemName, deltaValue)
	end
	return updated
end

local function finalizePlan(ctx)
	updatePresentCache(ctx)
	local missingItems = {}
	for itemName, wantAmount in pairs(ctx.nextItems) do
		wantAmount = wantAmount - ctx.presentCache[itemName].amount
		if wantAmount > 0 then
			table.insert(missingItems, {item = itemName, amount = wantAmount})
		end
	end
	local recipeQueue = {}
	for i = #ctx.recipeStack, 1, -1 do
		local stage = ctx.recipeStack[i]
		for recipeName, mult in pairs(stage) do
			table.insert(recipeQueue, {recipe = recipeName, amount = mult})
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

local function planForItem(itemName, amount)
	amount = amount or 1
	local ctx = makePlanContext(("Item %q * %d"):format(itemName, amount))
	wantItem(ctx, itemName, amount)
	updatePresentCache(ctx)
	wantItem(ctx, itemName, ctx.presentCache[itemName].amount)
	while stepPlan(ctx) do
		os.sleep(0.05)
	end
	return finalizePlan(ctx)
end

return {
	planForItem = planForItem,
}
