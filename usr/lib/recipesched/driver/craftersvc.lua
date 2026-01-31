local api = require "craftersvc.client.api"
local items = require "recipesched.items"
local recipes = require "recipesched.recipes"
local math = require "math"

-- For debug
local OFFLINE = false

local function countPresentItems(names)
	local unifiedList = {}
	local nameRanges = {}
	local nameStacks = {}
	for _, name in ipairs(names) do
		local rangeStart = #unifiedList + 1
		local specList, stacks = items.nameToSpecList(name)
		nameStacks[name] = stacks
		for _, spec in ipairs(specList) do
			table.insert(unifiedList, spec)
		end
		local rangeEnd = #unifiedList
		nameRanges[name] = {rangeStart, rangeEnd}
	end
	local apiResult
	if OFFLINE then
		apiResult = {}
		for _, spec in ipairs(unifiedList) do
			table.insert(apiResult, {specifiers = spec, amount = 0, slots = {}})
		end
	else
		-- Use slots to prevent double-counting
		apiResult = api.countItems(unifiedList, {withSlots = true})
	end
	local result = {}
	for _, name in ipairs(names) do
		local range = nameRanges[name]
		local bySlot = {}
		local forStacks = {}
		for i = range[1], range[2] do
			local stack = nameStacks[i - range[1] + 1]
			local entry = apiResult[i]
			table.insert(forStacks, {stack = stack, amount = entry.amount})
			for _, slotInfo in ipairs(entry.slots) do
				bySlot[slotInfo.s] = slotInfo.n
			end
		end
		local amount = 0
		for _, slotAmount in pairs(bySlot) do
			amount = amount + slotAmount
		end
		result[name] = {amount = amount, forStacks = forStacks}
	end
	return result
end

local function craft(grid, amount)
	local apiGrid = {}
	local batchSize = 64
	for y, row in ipairs(grid) do
		apiGrid[y] = {}
		for x, cell in ipairs(row) do
			if cell == recipes.EMPTY_SLOT then
				apiGrid[y][x] = false
			else
				local name = recipes.getRecipeItemName(cell)
				if not name then
					error(("Not an item: %q"):format(cell))
				end
				local specList = items.nameToSpecList(name)
				if #specList == 0 then
					error(("Unpopulated item %q"):format(name))
				end
				-- TODO accept enough information to handle #specList > 1
				local specifications = specList[1]
				batchSize = math.min(specifications.maxSize or 64, batchSize)
				apiGrid[y][x] = specifications
			end
		end
	end
	-- Avoid timeouts
	while amount > batchSize do
		api.craftGrid(apiGrid, batchSize)
		amount = amount - batchSize
	end
	api.craftGrid(apiGrid, amount)
end

return {
	countPresentItems = countPresentItems,
	craft = craft,
}
