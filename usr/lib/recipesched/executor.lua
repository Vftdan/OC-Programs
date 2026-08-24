local recipes = require "recipesched.recipes"
local infra = require "recipesched.infra"
local nodechoice = require "recipesched.nodechoice"
local stockcheck = require "recipesched.stockcheck"
local recipeCallbacks = require "recipesched.recipe_callbacks"
local drivers = require "recipesched.drivers"
local os = require "os"
local thread = require "thread"
local event = require "event"

local DELETION_DELAY = 72 * 60 * 20
local TERMINATION_TIMEOUT = 72 * 60 * 2

local function makeBlockingCallbackRecipe(ctx, recipeName, amount, defaultNodeName)
	local desc = recipes.registry[recipeName]
	local callback = recipeCallbacks[desc.callbackName]
	if not ctx.driverFeature then
		ctx.driverFeature = {}
	end
	local choice = nodechoice.chooseNodesForRecipe(recipeName, defaultNodeName)
	ctx.node = choice.node
	for feature, srvDescr in pairs(choice.driverFeatureServers) do
		local hostName = srvDescr.host
		local driverName = srvDescr.driver
		local driver = drivers.loadForHost(driverName, hostName)
		ctx.driverFeature[feature] = driver
	end
	if desc.blocking then
		return function()
			callback(ctx, desc.args, amount)
		end
	else
		local countGetter = nil
		local firstResult = desc.results[1]
		if firstResult then
			local itemName = recipes.getRecipeItemName(firstResult.item)
			local outputEntry = choice.itemOutputs[itemName]
			if not outputEntry.bad then
				local counter = stockcheck.combinedNodeCounter(outputEntry.nodes)
				local itemList = {itemName}
				countGetter = function()
					return counter(itemList)[itemName].amount
				end
			end
		end
		if not countGetter then
			return function()
				callback(ctx, desc.args, amount)
			end
		end
		return function()
			local desiredAmount = countGetter() + firstResult.amount * amount
			callback(ctx, desc.args, amount)
			while countGetter() < desiredAmount do
				-- TODO add timeout
				os.sleep(5)
			end
		end
	end
end

local function makeBlockingCallbackDelivery(itemName, srcName, dstName, amount)
	local dstNode = infra.nodeRegistry[dstName]
	if not dstNode then
		error(("Invalid delivery destination: %q"):format(dstName))
	end
	local srvDescr = dstNode.inputServer
	if not srvDescr then
		error(("Delivery to a node %q without an input server"):format(dstName))
	end
	if srvDescr.storage ~= srcName then
		error(("Delivery from a node %q not mathching the input storage %q of %q"):format(srcName, srvDescr.storage, dstName))
	end
	local hostName = srvDescr.host
	local driverName = srvDescr.driver
	if not drivers.hasAllFeatures(driverName, {"delivery"}) then
		error(("Input server driver %q of node %q does not implement delivery"):format(driverName, dstName))
	end
	local driver = drivers.loadForHost(driverName, hostName)
	local itemRef = recipes.itemGetter[itemName]
	local srcStockDriver = stockcheck.getNodeDriver(srcName)
	local outputNodes = nodechoice.followPossibleItemOutputs(dstName, itemName, amount)
	local dstCounter = outputNodes and stockcheck.combinedNodeCounter(outputNodes)
	return function()
		local itemList = {itemName}
		local order = {{ref = itemRef, amount = amount}}
		if srcStockDriver then
			while srcStockDriver.countPresentItems(itemList)[itemName].amount < amount do
				os.sleep(5)
			end
		end
		local desiredAmount
		if dstCounter then
			desiredAmount = dstCounter(itemList)[itemName].amount + amount
		end
		driver.deliver(dstNode.localName, order)
		if dstCounter then
			while dstCounter(itemList)[itemName].amount < desiredAmount do
				os.sleep(5)
			end
		end
	end
end

local function makeBlockingCallback(ctx, entry)
	if entry.recipe then
		return makeBlockingCallbackRecipe(ctx, entry.recipe, entry.amount, entry.node)
	elseif entry.deliver then
		return makeBlockingCallbackDelivery(entry.deliver, entry.from, entry.to, entry.amount)
	else
		error("Unknown plan entry type")
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

local function stringifyPlanEntry(entry)
	if entry.recipe then
		return ("%q * %d"):format(entry.recipe, entry.amount)
	elseif entry.deliver then
		return ("%q * %d -> %q"):format(entry.deliver, entry.amount, entry.to)
	else
		return tostring(entry)
	end
end

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
			callback = makeBlockingCallback({}, entry),
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
	for i = #jobQueue, 1, -1 do
		if jobQueue[i] == id then
			table.remove(jobQueue, i)
		end
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
