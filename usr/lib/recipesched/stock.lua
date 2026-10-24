local configloader = require "recipesched.configloader"
local lazytable = require "recipesched.lazytable"
local items = require "recipesched.items"
local infra = require "recipesched.infra"

local NODE_DEFAULT = lazytable.symbol("NODE_DEFAULT")
local stockTargetRegistry = {}

local itemRefs, itemGetter = lazytable.stringKeyRefs("item")
local nodeRefs, nodeGetter = lazytable.stringKeyRefs("node")

local function addStockTarget(registry, entry)
	if type(entry) ~= "table" then
		error("Stock entry is not a table")
	end
	local item = entry[1]
	if not item then
		error("Missing stock entry item")
	end
	if not itemRefs[item] then
		error("Invalid stock entry item")
	end
	local node = entry.at
	if node == nil then
		node = NODE_DEFAULT
	else
		if not nodeRefs[node] then
			error("Stock entry field `node`: a node expected")
		end
	end
	local amount = entry.amount
	if type(amount) ~= "number" then
		error(("Stock entry field `node`: a number expected, got: %s"):format(type(amount)))
	end
	local forNode = registry[node]
	if not forNode then
		forNode = {}
		registry[node] = forNode
	end
	local forItem = forNode[item]
	if not forItem then
		forItem = {}
		forNode[item] = forItem
	end
	table.insert(forItem, {amount = amount})
end

local function makeImports(newTargets)
	local imports = {
		item = itemGetter,
		node = nodeGetter,
		stock = function(...)
			return addStockTarget(newTargets, ...)
		end,
	}
	return imports
end

local function reload()
	local newTargets = {}
	local loaded = configloader.loadNamed("stock", {imports = makeImports(newTargets)})
	if not loaded then
		return false
	end
	for node in pairs(stockTargetRegistry) do
		stockTargetRegistry[node] = nil
	end
	for node, forNode in pairs(newTargets) do
		stockTargetRegistry[node] = forNode
	end
end

local function getNodeName(ref)
	if ref == NODE_DEFAULT then
		return infra.getDefaultStorageName()
	end
	return nodeRefs[ref]
end

local requestContextMeta = {}
requestContextMeta.__index = requestContextMeta

local function requestContext()
	return setmetatable({}, requestContextMeta)
end

function requestContextMeta:evaluateTerm(term)
	local _ = self
	return term.amount
end

function requestContextMeta:compose(registry)
	local request = {name = "Stock request"}
	for node, forNode in pairs(registry) do
		local nodeName = getNodeName(node)
		local nodeDescr = infra.nodeRegistry[nodeName]
		if not nodeDescr then
			error(("Undefined node: %q"):format(nodeName))
		end
		for item, forItem in pairs(forNode) do
			local itemName = itemRefs[item]
			local itemDescr = items.registry[itemName]
			if not itemDescr then
				error(("Undefined item: %q"):format(itemName))
			end
			local amount = 0
			for _, term in ipairs(forItem) do
				amount = amount + self:evaluateTerm(term)
			end
			if amount > 0 then
				table.insert(request, {
					item = itemName,
					at = nodeName,
					amount = amount,
					add = false,
				})
			end
		end
	end
	return request
end

local function composePlanRequest()
	local registrySnapshot = {}
	for node, forNode in pairs(stockTargetRegistry) do
		registrySnapshot[node] = forNode
	end
	return requestContext():compose(registrySnapshot)
end

return {
	reload = reload,
	composePlanRequest = composePlanRequest,
}
