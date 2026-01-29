local recipes = require "recipesched.recipes"
local recipeCallbacks = require "recipesched.recipe_callbacks"
local drivers = require "recipesched.drivers"
local craftersvc = require "recipesched.driver.craftersvc"
local os = require "os"

local DELETION_DELAY = 60 * 20

local function makeBlockingCallback(ctx, recipeName, amount)
	local desc = recipes.registry[recipeName]
	local callback = recipeCallbacks[desc.callbackName]
	if not ctx.driver then
		ctx.driver = {}
	end
	for _, name in ipairs(desc.drivers) do
		ctx.driver[name] = drivers.load(name)
	end
	if desc.blocking then
		return function()
			callback(ctx, desc.args, amount)
		end
	else
		local firstResult = desc.results
		if not firstResult then
			return function()
				callback(ctx, desc.args, amount)
			end
		end
		local itemName = recipes.getRecipeItemName(firstResult.item)
		return function()
			local response = craftersvc.countPresentItems({itemName})
			local desiredAmount = response[itemName].amount + firstResult.amount * amount
			callback(ctx, desc.args, amount)
			while craftersvc.countPresentItems({itemName})[itemName].amount < desiredAmount do
				-- TODO add timeout
				os.sleep(5)
			end
		end
	end
end

local function makeJobId()
	local builder = {}
	for i = 1, 10 do
		table.insert(builder, ("%x"):format(math.random(0, 15)))
	end
	return table.concat(builder)
end

local jobRegistry = {}
local jobQueue = {}
local deletionQueue = {}

local function registerJobFromPlan(plan)
	local id
	repeat
		id = makeJobId()
	until not jobRegistry[id]
	local job = {id = id, name = plan.name, steps = {}, lastStep = 0, created = false, active = false, finished = false}
	jobRegistry[id] = job
	for _, entry in ipairs(plan.recipeQueue) do
		table.insert(job.steps, {
			name = ("%q * %d"):format(entry.recipe, entry.amount),
			callback = makeBlockingCallback({}, entry.recipe, entry.amount),
		})
	end
	job.created = true
	table.insert(jobQueue, id)
	return id, #jobQueue
end

local function executorEntry()
	while true do
		local time = os.time()
		while true do
			local entry = deletionQueue[1]
			if not entry then
				break
			end
			if entry.time < time then
				jobRegistry[entry.id] = nil
				table.remove(deletionQueue, 1)
				break
			end
			os.sleep(0.05)
		end
		local nextJobId = table.remove(jobQueue, 1)
		if not nextJobId then
			os.sleep(5)
		else
			local job = jobRegistry[nextJobId]
			while not job.finished do
				if job.lastStep >= #job.steps then
					job.success = true
					job.finished = true
					break
				end
				job.active = true
				local stepNum = job.lastStep + 1
				local stepCb = job.steps[stepNum].callback
				local ok, reason = pcall(stepCb)
				if not ok then
					job.reason = reason
					job.success = false
					job.active = false
					job.finished = true
					break
				end
				job.lastStep = stepNum
				job.active = false
				os.sleep(0.05)
			end
			table.insert(deletionQueue, {
				id = nextJobId,
				time = os.time() + DELETION_DELAY,
			})
		end
	end
end

return {
	registerJobFromPlan = registerJobFromPlan,
	jobRegistry = jobRegistry,
	executorEntry = executorEntry,
}
