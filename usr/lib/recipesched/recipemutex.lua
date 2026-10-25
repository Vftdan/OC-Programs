local event = require "event"

local nodeOrdering = setmetatable({}, {__mode = "k"})
local lastNodeIndex = 0

local function getNodeIndex(node)
	local idx = nodeOrdering[node]
	if idx then
		return idx
	end
	lastNodeIndex = lastNodeIndex + 1
	idx = lastNodeIndex
	nodeOrdering[node] = idx
	return idx
end

local heldNodes = setmetatable({}, {__mode = "k"})

local function nodeComparator(lhs, rhs)
	local lidx = getNodeIndex(lhs)
	local ridx = getNodeIndex(rhs)
	return lidx < ridx
end

local function makeLockOwner(ctx)
	return {co = coroutine.running(), ctx = ctx}
end

local function isOwnerDead(owner)
	if not owner then
		return true
	end
	if owner.ctx.finished then  -- TODO
		return true
	end
	local st = coroutine.status(owner.co)
	if st == "dead" then
		return true
	end
end

local function acquireNode(node, owner)
	while not isOwnerDead(heldNodes[node]) do
		event.pull(0.5)
	end
	heldNodes[node] = owner
end

local function releaseNode(node, owner)
	local realOwner = heldNodes[node]
	if not realOwner then
		return
	end
	if not owner or realOwner.ctx == owner.ctx then
		heldNodes[node] = nil
	end
end

local function acquireForContext(ctx)
	local owner = makeLockOwner(ctx)
	local sortedNodes = {}
	for _, node in ipairs(ctx.blockingNodes or {}) do
		table.insert(sortedNodes, node)
	end
	table.sort(sortedNodes, nodeComparator)
	for _, node in ipairs(sortedNodes) do
		acquireNode(node, owner)
	end
end

local function releaseForContext(ctx)
	local owner = makeLockOwner(ctx)
	for _, node in ipairs(ctx.blockingNodes or {}) do
		releaseNode(node, owner)
	end
end

return {
	acquireForContext = acquireForContext,
	releaseForContext = releaseForContext,
}
