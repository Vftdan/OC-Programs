local recipes = require "recipesched.recipes"
local recipeCallbacks = require "recipesched.recipe_callbacks"
local drivers = require "recipesched.drivers"
local craftersvc = require "recipesched.driver.craftersvc"
local os = require "os"
local thread = require "thread"
local event = require "event"

local DELETION_DELAY = 72 * 60 * 20
local TERMINATION_TIMEOUT = 72 * 60 * 2

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
		local firstResult = desc.results[1]
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

local function executorEntry(ctx)
	ctx.thread = thread.current()
	while ctx.running do
		local time = os.time()
		while ctx.running do
			local entry = deletionQueue[1]
			if not entry then
				break
			end
			if entry.time < time then
				jobRegistry[entry.id] = nil
				table.remove(deletionQueue, 1)
			else
				break
			end
			os.sleep(0.05)
		end
		local nextJobId = table.remove(jobQueue, 1)
		ctx.heldJob = nextJobId
		if not nextJobId then
			os.sleep(5)
		else
			local job = jobRegistry[nextJobId]
			while not job.finished and ctx.running do
				if job.lastStep >= #job.steps then
					job.success = true
					job.finished = true
					break
				end
				job.active = true
				job.executor = ctx
				local stepNum = job.lastStep + 1
				local stepCb = job.steps[stepNum].callback
				local ok, reason = pcall(stepCb)
				job.executor = nil
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
			ctx.heldJob = nil
			if job.finished then
				table.insert(deletionQueue, {
					id = nextJobId,
					time = os.time() + DELETION_DELAY,
				})
			else
				table.insert(jobQueue, 1, nextJobId)
			end
		end
	end
end

local function makeExecutorContext()
	return {
		running = true,
	}
end

local function cleanupKilled(ctx)
	ctx.running = false
	if ctx.heldJob then
		local job = jobRegistry[ctx.heldJob]
		if job then
			if job.active then
				job.reason = "killed"
				job.success = false
				job.active = false
				job.finished = true
			end
		end
		table.insert(jobQueue, 1, ctx.heldJob)
		ctx.heldJob = nil
	end
	local onKill = ctx.onKill
	if onKill then
		onKill(ctx)
	end
end

local killQueue = {}
local killNextTimer = nil

local function killExecutorThread(ctx)
	local thr = ctx.thread
	if thr then
		thr:kill()
	end
	cleanupKilled(ctx)
end

local processKillQueue
local function updateKillNextTimer()
	if killNextTimer == nil then
		local ctx = killQueue[1]
		if not ctx then
			return
		end
		local deadline = killQueue[1].stopDeadline
		local remainingSec = (deadline - os.time()) / 72
		killNextTimer = event.timer(math.max(remainingSec, 0), processKillQueue)
	end
end

function processKillQueue()
	local ctx = table.remove(killQueue, 1)
	updateKillNextTimer()
	if ctx then
		killExecutorThread(ctx)
	end
end

local function stopExecutor(ctx, now)
	ctx.running = false
	if now then
		killExecutorThread(ctx)
	else
		ctx.stopDeadline = os.time() + TERMINATION_TIMEOUT
		table.insert(killQueue, ctx)
		updateKillNextTimer()
	end
end

-- Network API wrappers
local function wrapJobInfo(job)
	if type(job) ~= "table" then
		return job
	end
	local wrapped = {
		id = job.id,
		name = job.name,
		steps = {},
		lastStep = job.lastStep,
		created = job.created,
		active = job.active,
		finished = job.finished,
		success = job.success,
		reason = job.reason,
	}
	for i, step in ipairs(job.steps) do
		wrapped.steps[i] = {
			name = step.name,
		}
	end
	return wrapped
end

local function getJobInfo(id)
	return wrapJobInfo(jobRegistry[id])
end

local function getJobList()
	local keys = {}
	for id in pairs(jobRegistry) do
		table.insert(keys, id)
	end
	table.sort(keys)
	return keys
end

local function killJob(id)
	local job = jobRegistry[id]
	if not job then
		return false
	end
	local ctx = job.executor
	if ctx and job.active then
		stopExecutor(ctx)
	end
	job.reason = "killed"
	job.success = false
	job.active = false
	job.finished = true
	table.insert(deletionQueue, {
		id = id,
		time = os.time() + DELETION_DELAY,
	})
	return true
end

return {
	registerJobFromPlan = registerJobFromPlan,
	jobRegistry = jobRegistry,
	executorEntry = executorEntry,
	makeExecutorContext = makeExecutorContext,
	cleanupKilled = cleanupKilled,
	stopExecutor = stopExecutor,
	getJobInfo = getJobInfo,
	getJobList = getJobList,
	killJob = killJob,
}
