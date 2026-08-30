local configloader = require "recipesched.configloader"
local lazytable = require "recipesched.lazytable"
local reskinds = require "recipesched.reskinds"

local KIND_ITEM = reskinds.symbols.minecraft.item
local KIND_FLUID = reskinds.symbols.forge.fluid

local registry = {}

local modGetter
modGetter = lazytable.create(function(resKind)
	if type(resKind) ~= "table" then
		return modGetter[KIND_ITEM][resKind]
	end
	local kindDescr = reskinds.symbolToDescr[resKind]
	if not kindDescr then
		error("`mod` key: expected kind.*.*")
	end
	return lazytable.create(function (ns)
		return lazytable.create(function(name)
			return resKind[ns .. ":" .. name]
		end, {frozen = true, weak = true, toString = function() return ("mod[%s][%q]"):format(tostring(resKind), ns) end})
	end, {frozen = true, weak = true, toString = function() return ("mod[%s]"):format(tostring(resKind)) end})
end, {frozen = true, weak = true, toString = function() return "mod" end})

local loadImports = {
	mod = modGetter,
	mod_fluid = modGetter[KIND_FLUID],
	kind = reskinds.symbols,
}

local function processItem(tbl)
	if tbl and reskinds.symbolToDescr[tbl] then
		tbl = tbl[""]
	end
	if type(tbl) == "function" then
		tbl = tbl()
	end
	if type(tbl) ~= "table" then
		return false, ": table expected, got " .. type(tbl)
	end
	local kind = tbl.kind
	if type(kind) ~= "string" then
		return false, ".kind: string expected, got " .. type(kind)
	end
	if kind == "stack" then
		local resource = tbl.res
		if type(resource) ~= "table" then
			return false, ".res: table expected, got " .. type(resource)
		end
		local resNs, resKind = resource.ns, resource.kind
		if type(resNs) ~= "string" then
			return false, ".res.ns: string expected, got " .. type(resNs)
		end
		if type(resKind) ~= "string" then
			return false, ".res.kind: string expected, got " .. type(resKind)
		end
		local kindDescr = reskinds.descrs[resNs][resKind]
		local ok, value = kindDescr:finalizeValue(tbl.value)
		if not ok then
			return false, ".value" .. value
		end
		return true, {kind = "stack", res = {ns = resNs, kind = resKind}, value = value}
	else
		-- TODO alternative kind
		return false, (".kind: unknown value %q"):format(kind)
	end
end

local function reload()
	local loaded = configloader.loadNamed("items", {imports = loadImports})
	if not loaded then
		return false
	end
	local newRegistry = {}
	for k, v in pairs(loaded.globals) do
		local ok, newV = processItem(v)
		if not ok then
			error("Config entry " .. tostring(k) .. newV)
		end
		newRegistry[k] = newV
	end
	for k in pairs(registry) do
		registry[k] = nil
	end
	for k, v in pairs(newRegistry) do
		registry[k] = v
	end
	return true
end

local function populateStacks(stackArray, node, kindDescr)
	if node.kind == "stack" then
		if kindDescr:matches(node) then
			table.insert(stackArray, node.value)
		end
	end
end

local function populateKinds(kindSet, node)
	if node.kind == "stack" then
		kindSet[reskinds.descrs[node.res.ns][node.res.kind]] = true
	end
end

local function lookupStacks(name, kindDescr)
	local entry = registry[name]
	if not entry then
		return nil
	end
	local result = {}
	populateStacks(result, entry, kindDescr)
	return result
end

local function lookupKinds(name)
	local entry = registry[name]
	if not entry then
		return nil
	end
	local result = {}
	populateKinds(result, entry)
	return result
end

local function nameToSpecList(name, opts)
	opts = opts or {}
	local kindDescr = reskinds.fromResPair(opts.res) or reskinds.symbolToDescr[KIND_ITEM]
	local specList = {}
	local stacks = lookupStacks(name, kindDescr)
	if not stacks then
		error(("Unknown item %q"):format(name))
	end
	for _, stack in ipairs(stacks) do
		table.insert(specList, kindDescr:getSpecifiers(stack))
	end
	return specList, stacks
end

local function nameToKindList(name)
	local kindSet = lookupKinds(name)
	if not kindSet then
		error(("Unknown item %q"):format(name))
	end
	local kindList = {}
	for kindDescr in pairs(kindSet) do
		table.insert(kindList, kindDescr)
	end
	return kindList
end

-- Network API wrappers
local function getRegistryElement(key)
	return registry[key]
end

local function getRegistryKeys()
	local result = {}
	for key in pairs(registry) do
		table.insert(result, key)
	end
	table.sort(result)
	return result
end

return {
	registry = registry,
	reload = reload,
	nameToSpecList = nameToSpecList,
	nameToKindList = nameToKindList,
	getRegistryElement = getRegistryElement,
	getRegistryKeys = getRegistryKeys,
}
