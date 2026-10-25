local recipes = require "recipesched.recipes"
local infra = require "recipesched.infra"
local nodechoice = require "recipesched.nodechoice"
local stockcheck = require "recipesched.stockcheck"
local recipeCallbacks = require "recipesched.recipe_callbacks"
local drivers = require "recipesched.drivers"
local recipemutex = require "recipesched.recipemutex"
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
	if not ctx.blockingNodes then
		ctx.blockingNodes = {}
	end
	local choice = nodechoice.chooseNodesForRecipe(recipeName, defaultNodeName)
	ctx.node = choice.node
	if choice.node and choice.node.isProcessor and choice.node.isBlocking then
		table.insert(ctx.blockingNodes, choice.node)
	end
	for feature, srvDescr in pairs(choice.driverFeatureServers) do
		local hostName = srvDescr.host
		local driverName = srvDescr.driver
		local driver = drivers.loadForHost(driverName, hostName)
		ctx.driverFeature[feature] = driver
	end
	if desc.blocking then
		return function()
			recipemutex.acquireForContext(ctx)
			callback(ctx, desc.args, amount)
			recipemutex.releaseForContext(ctx)
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
				recipemutex.acquireForContext(ctx)
				callback(ctx, desc.args, amount)
				recipemutex.releaseForContext(ctx)
			end
		end
		return function()
			local desiredAmount = countGetter() + firstResult.amount * amount
			recipemutex.acquireForContext(ctx)
			callback(ctx, desc.args, amount)
			while countGetter() < desiredAmount do
				-- TODO add timeout
				os.sleep(5)
			end
			recipemutex.releaseForContext(ctx)
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

local function assertConcurrencyIdType(id)
	local t = type(id)
	if t == "string" or t == "number" then
		return id
	end
	error(("Illegal concurrency id type: %s"):format(t))
end

local function makeStepConcurrency(entry)
	local result = {nextList = {}, nextSet = {}}
	local info = entry.conc
	if info then
		result.id = assertConcurrencyIdType(info[1])
		local nextList, nextSet = result.nextList, result.nextSet
		for i = 2, #info do
			local nextId = assertConcurrencyIdType(info[i])
			table.insert(nextList, nextId)
			nextSet[nextId] = true
		end
	end
	return result
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
	local concIdToIdx = {}
	local job = {id = id, name = plan.name, steps = {}, lastStep = 0, created = false, active = false, finished = false, concIdToIdx = concIdToIdx}
	jobRegistry[id] = job
	for _, entry in ipairs(plan.recipeQueue) do
		local step = {
			name = ("%q * %d"):format(entry.recipe, entry.amount),
			callback = makeBlockingCallback({}, entry),
			concurrency = makeStepConcurrency(entry),
		}
		table.insert(job.steps, step)
		local concId = step.concurrency.id
		if concId then
			concIdToIdx[concId] = #job.steps
		end
	end
	job.created = true
	table.insert(jobQueue, id)
	return id, #jobQueue
end

local ConcurrencyTracker = {}
ConcurrencyTracker.__index = ConcurrencyTracker

function ConcurrencyTracker:new()
	return setmetatable({active = {}, activeIds = {}, finishedIds = {}, foreground = nil, nextIdx = 0}, self)
end

function ConcurrencyTracker:enterStep(step)
	self.active[step] = true
	local id = step.concurrency.id
	if id then
		self.activeIds[id] = true
	end
end

function ConcurrencyTracker:leaveStep(step)
	local id = step.concurrency.id
	if id then
		self.activeIds[id] = nil
		self.finishedIds[id] = true
	end
	self.active[step] = nil
	if self.foreground == step then
		self.foreground = nil
	end
end

function ConcurrencyTracker:setForeground(step)
	self.foreground = step
	self.nextIdx = 1
end

function ConcurrencyTracker:isAllowedId(id)
	for node in pairs(self.active) do
		if not node.concurrency.nextSet[id] then
			return false
		end
	end
	return true
end

function ConcurrencyTracker:findAllowedId()
	local fg = self.foreground
	if not fg then
		return nil
	end
	local lst = fg.concurrency.nextList
	local rewound = false
	while true do
		while self.nextIdx > #lst do
			if rewound then
				return nil
			end
			rewound = true
			self.nextIdx = 1
		end
		local id = lst[self.nextIdx]
		if not self.activeIds[id] and not self.finishedIds[id] then
			if self:isAllowedId(id) then
				return id
			end
		end
		self.nextIdx = self.nextIdx + 1
	end
end

function ConcurrencyTracker:banId(id)
	self.finishedIds[id] = true
end

local function backgroundStepEntry(step)
	local stepCb = step.callback
	step.result = table.pack(xpcall(stepCb, debug.traceback))
end

local function runBackground(step)
	if step.bgThread then
		return
	end
	step.bgThread = thread.create(backgroundStepEntry, step)
end

local function protectedForeground(step)
	local bgThread = step.bgThread
	if bgThread then
		while not bgThread:status() == "dead" do
			event.pull()
		end
		local result = step.result or {false, "dead", n = 2}
		return table.unpack(result, 1, result.n)
	end
	local stepCb = step.callback
	return xpcall(stepCb, debug.traceback)
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
				local tracker = job.concurrencyTracker
				if not tracker then
					tracker = ConcurrencyTracker:new()
					job.concurrencyTracker = tracker
				end
				local stepNum = job.lastStep + 1
				local fgStep = job.steps[stepNum]
				tracker:enterStep(fgStep)
				tracker:setForeground(fgStep)
				while true do
					local bgId = tracker:findAllowedId()
					if not bgId then
						break
					end
					local idx = job.concIdToIdx[bgId]
					if not idx or idx > #job.steps then
						tracker:banId(bgId)
					else
						local bgStep = job.steps[idx]
						tracker:enterStep(bgStep)
						runBackground(bgStep)
					end
				end
				local ok, reason = protectedForeground(fgStep)
				-- TODO consider checking for completed background steps
				tracker:leaveStep(fgStep)
				job.executor = nil
				if not ok then
					local nlpos = reason:find("\n") or #reason + 1
					job.reason = reason:sub(1, nlpos - 1)
					job.stacktrace = reason:sub(nlpos + 1)
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
		stacktrace = job.stacktrace,
	}
	for i, step in ipairs(job.steps) do
		local bgThread = step.bgThread
		wrapped.steps[i] = {
			name = step.name,
			bg = bgThread and bgThread:status() ~= "dead",
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
