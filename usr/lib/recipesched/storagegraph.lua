local lazytable = require "recipesched.lazytable"
local infra = require "recipesched.infra"
local reskinds = require "recipesched.reskinds"
local drivers = require "recipesched.drivers"
local util = require "recipesched.util"
local stablepqueue = require "recipesched.stablepqueue"

local KIND_ITEM = reskinds.descrs.minecraft.item
local ANY_KIND = lazytable.symbol("ANY_KIND")
local STORAGE_FEATURES = {}
local WAIT_AUTO_FEATURES = {"stockCount"}
local EMPTY_SPEC = {}

local function kindsEqual(lhs, rhs)
	if lhs == rhs then
		return true
	end
	if lhs == ANY_KIND then
		return true
	end
	if rhs == ANY_KIND then
		return true
	end
	return false
end

local function getDriverNames(node, unsorted)
	local driverNames = {}
	for k in pairs(node.servedDrivers) do
		table.insert(driverNames, k)
	end
	if not unsorted then
		table.sort(driverNames)
	end
	return driverNames
end

local function hasAllFeatures(node, features)
	local driverNames = getDriverNames(node, true)
	for _, feature in ipairs(features) do
		if #drivers.getFactoriesWithFeature(feature, driverNames) == 0 then
			return false
		end
	end
	return true
end

local function isStorageNode(node)
	if node.isProcessor then
		return false
	end
	return hasAllFeatures(node, STORAGE_FEATURES)
end

local NON_STORAGE = lazytable.symbol("NON_STORAGE")
local STOP_AUTO = lazytable.symbol("STOP_AUTO")

local function build()
	local storageNodeSet = {}
	local storageNodes = {}
	local waitableNodeSet = {}
	local registry = infra.nodeRegistry
	for k, v in pairs(registry) do
		if isStorageNode(v) then
			storageNodeSet[k] = true
			table.insert(storageNodes, k)
			if hasAllFeatures(v, WAIT_AUTO_FEATURES) then
				waitableNodeSet[k] = true
			end
		end
	end
	table.sort(storageNodes)

	local edges = {}
	-- Populate auto-output edges
	for _, outNode in ipairs(storageNodes) do
		for _, route in ipairs(registry[outNode].autoOut) do
			local inNode = route[2]
			if not storageNodeSet[inNode] then
				inNode = NON_STORAGE
			elseif inNode == outNode then
				inNode = STOP_AUTO
			end
			table.insert(edges, {
				from = outNode,
				to = inNode,
				auto = true,
				cost = route[3] or 10,
				filter = route[1],
				kindFilter = route[4] or ANY_KIND,
			})
		end
	end
	-- Populate delivery edges
	for _, inNode in ipairs(storageNodes) do
		local inNodeValue = registry[inNode]
		local inputServer = inNodeValue.inputServer
		if inputServer then
			local outNode = inputServer.storage
			if outNode and storageNodeSet[outNode] then
				table.insert(edges, {
					from = outNode,
					to = inNode,
					auto = false,
					cost = inNodeValue.inputCost or 10,
					filter = EMPTY_SPEC,
					kindFilter = ANY_KIND,
				})
			end
		end
	end

	local outgoing = {}
	local ingoing = {}

	for _, e in ipairs(edges) do
		local inNode = e.to
		local outNode = e.from
		e.waitable = waitableNodeSet[inNode] or false
		local outList = outgoing[outNode]
		if not outList then
			outList = {}
			outgoing[outNode] = outList
		end
		local inList = ingoing[inNode]
		if not inList then
			inList = {}
			ingoing[inNode] = inList
		end
		table.insert(outList, e)
		table.insert(inList, e)
	end

	return storageNodeSet, outgoing, ingoing
end

local validForVersion = 0
local storageNodeSet = {}
local outgoing = {}
local ingoing = {}

local function checkStateVersion()
	local lastVersion = infra.getStateVersion()
	if validForVersion ~= lastVersion then
		storageNodeSet, outgoing, ingoing = build()
		validForVersion = lastVersion
	end
end

local function cachedIsStorageNode(nodeName)
	checkStateVersion()
	return storageNodeSet[nodeName] or false
end

local function cons(edge, tail)
	local path = {edge}
	for i = 1, #tail do
		path[i + 1] = tail[i]
	end
	return path
end

local function edgeMatchesAny(edge, stacks, kindDescr)
	local filter = edge.filter
	if edge.kindFilter then
		if not kindsEqual(edge.kindFilter, kindDescr) then
			return false
		end
	end
	if next(filter) == nil then
		-- Special case: empty filter matches an item stack event from an empty collection
		return true
	end
	for _, item in ipairs(stacks) do
		if util.matchItemSpec(item, filter) then
			return true
		end
	end
	return false
end

local function edgeMatchesAll(edge, stacks, kindDescr)
	local filter = edge.filter
	if edge.kindFilter then
		if not kindsEqual(edge.kindFilter, kindDescr) then
			return false
		end
	end
	for _, item in ipairs(stacks) do
		if not util.matchItemSpec(item, filter) then
			return false
		end
	end
	return true
end

local function areInterceptedBefore(edge, stacks, kindDescr)
	local sourceName = edge.from
	local adjEdges = outgoing[sourceName]
	if not adjEdges then
		return false  -- Should we throw an error/put an assertion?
	end
	for _, sibling in ipairs(adjEdges) do
		if sibling == edge then
			return false
		end
		if sibling.auto then
			if not edge.auto and sibling.to == STOP_AUTO then
				if edgeMatchesAll(sibling, stacks, kindDescr) then
					return false
				end
			else
				if edgeMatchesAny(sibling, stacks, kindDescr) then
					return true
				end
			end
		end
	end
	return false  -- Should we throw an error?
end

local function iterateIngoingPaths(nodeName, stacks, opts)
	opts = opts or {}
	local kindDescr = reskinds.fromResPair(opts.res) or KIND_ITEM
	if opts.anyRes then
		kindDescr = ANY_KIND
	end
	checkStateVersion()
	local version = validForVersion
	stacks = stacks or {}
	local visited = {}
	local queue = stablepqueue.create()
	queue:put(0, {nodeName, {}, false})
	return function()
		if version ~= validForVersion then
			error("Stale storage graph")
		end
		local cost, entry
		while true do
			cost, entry = queue:take()
			if not cost or not entry then
				return nil
			end
			if visited[entry[1]] then
				-- continue
			else
				break
			end
		end
		local pivot, path, expectWaitable = entry[1], entry[2], entry[3]
		visited[pivot] = true
		local nextEdges = ingoing[pivot]
		if nextEdges then
			for _, inEdge in ipairs(nextEdges) do
				if (inEdge.waitable or not expectWaitable) and edgeMatchesAll(inEdge, stacks, kindDescr) and not areInterceptedBefore(inEdge, stacks, kindDescr) then
					queue:put(cost + inEdge.cost, {inEdge.from, cons(inEdge, path), not inEdge.auto})
				end
			end
		end
		return pivot, path
	end
end

local function findIngoingPath(srcSet, nodeName, stacks, opts)
	for srcName, path in iterateIngoingPaths(nodeName, stacks, opts) do
		if srcSet[srcName] then
			return srcName, path
		end
	end
end

return {
	isStorageNode = cachedIsStorageNode,
	iterateIngoingPaths = iterateIngoingPaths,
	findIngoingPath = findIngoingPath,
}
