local items = require "craftersvc.common.items"
local config = require "craftersvc.common.config"
local component = require "component"

local function planForGrid(transposer, side, grid, amount)
	if amount < 1 then
		error("Cannot craft less than 1 time")
	end
	if amount > 64 then
		error("Robot can only craft in input batches of up to 64")
	end
	local remaining = {}
	local remainingAmount = 0
	for y, row in ipairs(grid) do
		if y > 3 then
			error("Too many rows")
		end
		for x, specifiers in ipairs(row) do
			if x > 3 then
				error("Too many columns in row " .. tostring(y))
			end
			if specifiers then
				table.insert(remaining, {amount = amount, x = x, y = y, specifiers = specifiers})
				remainingAmount = remainingAmount + amount
			end
		end
	end
	local plan = {}
	for y = 1, 3 do
		local row = {}
		for x = 1, 3 do
			local queue = {}
			row[x] = queue
		end
		plan[y] = row
	end
	local i = 0
	for stack in transposer.getAllStacks(side) do
		if remainingAmount < 1 then
			break
		end
		i = i + 1
		if stack and stack.name ~= "minecraft:air" then
			local stackSize = stack.size
			for _, entry in ipairs(remaining) do
				if items.matches(stack, entry.specifiers) then
					local transfered = entry.amount
					if transfered > stackSize then
						transfered = stackSize
					end
					table.insert(plan[entry.y][entry.x], {slot = i, amount = transfered})
					stackSize = stackSize - transfered
					entry.amount = entry.amount - transfered
					remainingAmount = remainingAmount - transfered
				end
			end
		end
	end
	-- TODO rebalance in case of missing repeated items
	for _, entry in ipairs(remaining) do
		if #plan[entry.y][entry.x] < 1 then
			return nil
		end
	end
	return plan
end

local function getTransposer(cfg)
	cfg = cfg or {}
	local uuid = config.get(cfg, {"transposer"})
	local transposer = component.transposer
	if uuid then
		transposer = component.proxy(uuid)
		if not transposer then
			error("The configured transposer doesn't exist")
		end
		if transposer.type ~= "transposer" then
			error("Not a transposer")
		end
	end
	if not transposer then
		error("No transposers connected")
	end
	local side = config.get(cfg, {"transposerSide"})
	if side then
		local size = transposer.getInventorySize(side)
		if not size then
			error("No inventory at the configured transposer side")
		end
		return transposer, side
	end
	for side = 0, 5 do
		local size = transposer.getInventorySize(side)
		if size and size > 0 then
			return transposer, side
		end
	end
	error("The transposer is not connected to the inventory")
end

local function countItems(transposer, side, specList, opts)
	local result = {}
	local withSlots = opts.withSlots or false
	for _, specifiers in ipairs(specList) do
		local entry = {specifiers = specifiers, amount = 0}
		if withSlots then
			entry.slots = {}
		end
		table.insert(result, entry)
	end
	if #result < 1 then
		return result
	end
	local i = 0
	for stack in transposer.getAllStacks(side) do
		i = i + 1
		if stack and stack.name ~= "minecraft:air" then
			local stackSize = stack.size
			for _, entry in ipairs(result) do
				if items.matches(stack, entry.specifiers) then
					entry.amount = entry.amount + stackSize
					if withSlots then
						table.insert(entry.slots, {s = i, n = stackSize})
					end
				end
			end
		end
	end
	return result
end

return {
	planForGrid = planForGrid,
	getTransposer = getTransposer,
	countItems = countItems,
}
