local configloader = require "recipesched.configloader"
local lazytable = require "recipesched.lazytable"
local items = require "recipesched.items"
local util = require "recipesched.util"

local registry = {}
local fromResults = lazytable.create(function() return {} end, {iterable = true})  -- name-to-name-set

local EMPTY_SLOT = lazytable.create(function() end, {frozen = true, toString = function() return "empty" end})

local itemRefs = setmetatable({}, {__mode = "k"})

local function toStringItemRef(ref)
	return ("item[%q]"):format(itemRefs[ref])
end

local itemGetter = lazytable.create(function(regName)
	if type(regName) ~= "string" then
		error("Non-string item reference")
	end
	local symbol = lazytable.create(function() end, {frozen = true, toString = toStringItemRef})
	itemRefs[symbol] = regName
	return symbol
end, {frozen = true, weak = true, toString = function() return "item" end})

local function deliveryBaseType(opts)
	local destination = opts.destination
	if type(destination) ~= "string" then
		error("Delivery destination is not a string")
	end
	local cart = opts.items
	if type(cart) ~= "table" then
		error("Delivery items is not a table")
	end
	local dependencies = {}
	local cartCopy = {}
	for i, cell in ipairs(cart) do
		if type(cell) ~= "table" then
			error(("Delivery item %d is not a table"):format(i))
		end
		local ref = cell.item
		local inputAmount = cell.amount
		if ref == nil then
			error(("Delivery item %d is missing a required field `item`"):format(i))
		end
		if inputAmount == nil then
			inputAmount = 1
		end
		if type(inputAmount) ~= "number" then
			error(("Delivery item %d amount is not a number"):format(i))
		end
		local itemName = itemRefs[ref]
		if not itemName then
			error(("Delivery item %d is not an item"):format(i))
		end
		cartCopy[i] = {item = ref, amount = inputAmount}
		dependencies[itemName] = (dependencies[itemName] or 0) + inputAmount
	end
	local resultsCopy = {}
	local results = opts.results
	if results ~= nil then
		if type(results) ~= "table" then
			error("Delivery results is not a table")
		end
		for i, cell in ipairs(results) do
			if type(cell) ~= "table" then
				error(("Delivery result %d is not a table"):format(i))
			end
			local ref = cell.item
			local outputAmount = cell.amount
			if ref == nil then
				error(("Delivery result %d is missing a required field `item`"):format(i))
			end
			if outputAmount == nil then
				outputAmount = 1
			end
			if type(outputAmount) ~= "number" then
				error(("Delivery result %d amount is not a number"):format(i))
			end
			local itemName = itemRefs[ref]
			if not itemName then
				error(("Delivery result %d is not an item"):format(i))
			end
			resultsCopy[i] = {item = ref, amount = outputAmount}
		end
	end
	local priority = opts.priority
	if priority == nil then
		priority = 0
	end
	if type(priority) ~= "number" then
		error("Recipe priority is not a number")
	end
	local descriptor = {
		drivers = {"delivery"},
		blocking = false,
		args = {destination = destination, cart = cartCopy},
		results = resultsCopy,
		dependencies = dependencies,
		priority = priority,
	}
	return descriptor
end

local recipeTypes = {
	craft = function(opts)
		if type(opts) ~= "table" then
			error("Non-table `craft` options")
		end
		local grid = opts.grid
		if type(grid) ~= "table" then
			error("Crafting recipe grid is not a table")
		end
		if #grid > 3 then
			error("Crafting grid has too many rows")
		end
		local dependencies = {}
		local gridCopy = {}
		for y, row in ipairs(grid) do
			if #row > 3 then
				error(("Crafting grid row %d has too many columns"):format(y))
			end
			local rowCopy = {}
			for x, cell in ipairs(row) do
				local itemName = itemRefs[cell]
				if cell ~= EMPTY_SLOT and not itemName then
					error(("Crafting grid has non-item cell at row %d column %d"):format(y, x))
				end
				rowCopy[x] = cell
				if cell ~= EMPTY_SLOT then
					dependencies[itemName] = (dependencies[itemName] or 0) + 1
				end
			end
			gridCopy[y] = rowCopy
		end
		local amount = opts.amount
		if amount == nil then
			amount = 1
		end
		if type(amount) ~= "number" then
			error("Crafting result amount is not a number")
		end
		local resultsCopy = {}
		local results = opts.results
		if results ~= nil then
			if type(results) ~= "table" then
				error("Crafting recipe results is not a table")
			end
			for i, cell in ipairs(results) do
				if not itemRefs[cell] then
					error(("Crafting result %d is not an item"):format(i))
				end
				local currentAmount = 1
				if i == 1 then
					currentAmount = amount
				end
				resultsCopy[i] = {item = cell, amount = currentAmount}
			end
		end
		local priority = opts.priority
		if priority == nil then
			priority = 0
		end
		if type(priority) ~= "number" then
			error("Recipe priority is not a number")
		end
		local descriptor = {
			drivers = {"craftersvc"},
			blocking = true,
			args = {grid = gridCopy},
			results = resultsCopy,
			dependencies = dependencies,
			callbackName = "craft",
			priority = priority,
		}
		return descriptor
	end,
	drone_deliver = function(opts)
		if type(opts) ~= "table" then
			error("Non-table `drone_deliver` options")
		end
		local descriptor = deliveryBaseType(opts)
		descriptor.callbackName = "ddrone_deliver"
		return descriptor
	end,
	wired_deliver = function(opts)
		if type(opts) ~= "table" then
			error("Non-table `wired_deliver` options")
		end
		local descriptor = deliveryBaseType(opts)
		descriptor.callbackName = "wired_deliver"
		return descriptor
	end,
}

local function wrapRecipeType(name, recipeRefs, f)
	local function recipeTypeWrapper(...)
		local origArgs = table.pack(...)
		local descriptor = f(...)
		local symbol = lazytable.create(function() end, {frozen = true, toString = function() return name .. util.serializeArgs(table.unpack(origArgs, 1, origArgs.n)) end})
		recipeRefs[symbol] = descriptor
		return symbol
	end
	return recipeTypeWrapper
end

local makeImports = function(recipeRefs)
	local imports = {}
	for k, v in pairs(recipeTypes) do
		imports[k] = wrapRecipeType(k, recipeRefs, v)
	end
	imports.item = itemGetter
	imports.empty = EMPTY_SLOT
	return imports
end

local function reload()
	local recipeRefs = {}
	local loaded = configloader.loadNamed("recipes", {imports = makeImports(recipeRefs)})
	if not loaded then
		return false
	end
	local newRegistry = {}
	for k, v in pairs(loaded.globals) do
		local descriptor = recipeRefs[v]
		if not descriptor then
			error("Config entry " .. tostring(k) .. ": not a recipe")
		end
		newRegistry[k] = descriptor
	end
	for k in pairs(registry) do
		registry[k] = nil
	end
	for k in pairs(fromResults) do
		fromResults[k] = nil
	end
	for k, v in pairs(newRegistry) do
		registry[k] = v
		for _, resultEntry in ipairs(v.results) do
			local itemRef = resultEntry.item
			local itemName = itemRefs[itemRef]
			local inputAmount = v.dependencies[itemName] or 0
			if resultEntry.amount > inputAmount then
				fromResults[itemName][k] = true
			end
		end
	end
	return true
end

local function getRecipeItemName(ref)
	return itemRefs[ref]
end

local function namePrioritiesGt(lhsName, rhsName)
	local lhsDesc = registry[lhsName]
	local rhsDesc = registry[rhsName]
	return lhsDesc.priority > rhsDesc.priority
end

local function recipesForResult(itemName)
	local recipeSet = fromResults[itemName]
	local recipeNames = {}
	for k in pairs(recipeSet) do
		table.insert(recipeNames, k)
	end
	if #recipeNames < 1 then
		fromResults[itemName] = nil
	end
	table.sort(recipeNames, namePrioritiesGt)
	return recipeNames
end

local function recipeResultAmount(recipeName, itemName)
	local descriptor = registry[recipeName]
	local amount = 0
	for _, entry in ipairs(descriptor.results) do
		if itemRefs[entry.item] == itemName then
			amount = amount + entry.amount
		end
	end
	return amount
end

return {
	registry = registry,
	reload = reload,
	fromResults = fromResults,
	getRecipeItemName = getRecipeItemName,
	recipesForResult = recipesForResult,
	recipeResultAmount = recipeResultAmount,
	EMPTY_SLOT = EMPTY_SLOT,
}
