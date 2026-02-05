local sides = require "sides"
local boundStorage = require "craftersvc.robot.boundStorage"
local items = require "craftersvc.common.items"
local component = require "component"
local crafting, inventory_controller, robot

local function scanComponents()
	crafting = component.crafting
	inventory_controller = component.inventory_controller
	robot = component.robot
end

scanComponents()

local function withStorage(ctx, cb, ...)
	-- Move to inventory here
	local side = ctx.storageSide or sides.front
	local storage = boundStorage.bindStorage(robot, inventory_controller, side)
	local size, reason = storage.getInventorySize()
	if not size then
		error("Couldn't create a bound storage: " .. tostring(reason))
	end
	local result = table.pack(pcall(cb, storage, ...))
	-- Move to the starting position here
	if result[1] then
		return table.unpack(result, 2, result.n)
	else
		error(table.unpack(result, 2, result.n))
	end
end

local function clearInventoryCallback(storage)
	local hasErrors = false
	local lastReason  -- FIXME unlike dropIntoSlot, drop doesn't seem to return failure reason
	for slot = 1, robot.inventorySize() do
		while robot.count(slot) > 0 do
			robot.select(slot)
			local success, reason = storage.drop()
			if not success then
				hasErrors = true
				lastReason = reason
			end
		end
	end
	if hasErrors then
		error("Couldn't clear the inventory: " .. tostring(lastReason))
	end
end

local function clearInventory(ctx)
	return withStorage(ctx, clearInventoryCallback)
end

local function performCraft(remaining)
	local crafted = 0
	local outputSlot = 13
	while true do
		if robot.inventorySize() < outputSlot then
			break
		end
		robot.select(outputSlot)
		outputSlot = outputSlot + 1
		local hasItems = true
		for _, entry in ipairs(remaining) do
			if robot.count(entry.slot) < 1 then
				hasItems = false
				break
			end
		end
		if not hasItems then
			break
		end
		if not crafting.craft() then
			error("Failed to craft")
		end
		crafted = crafted + robot.count()
	end
	return crafted
end

local function craftGridCallback(storage, grid, amount)
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
				table.insert(remaining, {amount = amount, slot = (y - 1) * 4 + x, specifiers = specifiers})
				remainingAmount = remainingAmount + amount
			end
		end
	end
	for i = 1, storage.getInventorySize() do
		if remainingAmount < 1 then
			break
		end
		local stack = storage.getStackInSlot(i)
		if stack then
			for _, entry in ipairs(remaining) do
				if items.matches(stack, entry.specifiers) then
					robot.select(entry.slot)
					local oldCount = robot.count()
					storage.suckFromSlot(i, entry.amount)
					-- TODO: detect overflow into the next available slot
					local transfered = robot.count() - oldCount
					entry.amount = entry.amount - transfered
					remainingAmount = remainingAmount - transfered
				end
			end
		end
	end
	-- TODO rebalance in case of missing repeated items
	return performCraft(remaining)
end

-- grid is a 2d array, with elements being a table or false
-- amount is the number of times to perform the crafting, not the number of resulting items
-- returns the number of resulting items
local function craftGrid(ctx, grid, amount)
	if amount < 1 then
		error("Cannot craft less than 1 time")
	end
	if amount > 64 then
		error("Robot can only craft in input batches of up to 64")
	end
	return withStorage(ctx, craftGridCallback, grid, amount)
end

local function craftFromPlanCallback(storage, plan, opts)
	opts = opts or {}
	local validateGrid = opts.validateGrid
	local remaining = {}
	for y = 1, 3 do
		local row = plan[y]
		for x = 1, 3 do
			local queue = row[x]
			if #queue > 0 then
				local robotSlot = (y - 1) * 4 + x
				table.insert(remaining, {slot = robotSlot})
				robot.select(robotSlot)
				for _, entry in ipairs(queue) do
					storage.suckFromSlot(entry.slot, entry.amount)
					-- Clear slot overflow
					robot.select(robotSlot + 1)
					storage.drop()
					robot.select(robotSlot)
				end
				if validateGrid then
					local specifiers = (validateGrid[y] or {})[x]
					if not specifiers then
						return "INVALID"
					end
					local stack = inventory_controller.getStackInInternalSlot()
					if not items.matches(stack, specifiers) then
						return "INVALID"
					end
				end
			end
		end
	end
	return performCraft(remaining)
end

local function craftFromPlan(ctx, plan, opts)
	return withStorage(ctx, craftFromPlanCallback, plan, opts)
end

return {
	scanComponents = scanComponents,
	clearInventory = clearInventory,
	craftGrid = craftGrid,
	craftFromPlan = craftFromPlan,
}
