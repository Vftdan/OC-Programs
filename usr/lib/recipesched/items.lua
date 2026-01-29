local configloader = require "recipesched.configloader"
local lazytable = require "recipesched.lazytable"

local registry = {}

-- FIXME memory leak
local modGetter = lazytable.create(function(ns)
	return lazytable.create(function(name)
		return function(fields)
			fields = fields or {}
			return {
				kind = "stack",
				value = {
					name = ns .. ":" .. name,
					damage = fields.damage,
				},
			}
		end
	end, {frozen = true, toString = function() return ("mod[%q][%q]"):format(ns, name) end})
end, {frozen = true, toString = function() return ("mod[%q]"):format(ns) end})

local loadImports = {
	mod = modGetter,
}

local function processItem(tbl)
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
		local stack = tbl.value
		if type(stack) ~= "table" then
			return false, ".value: table expected, got " .. type(stack)
		end
		local name = stack.name
		if type(name) ~= "string" then
			return false, ".value.name: string expected, got " .. type(name)
		end
		local damage = stack.damage
		if damage ~= nil and type(damage) ~= "number" then
			return false, ".value.damage: number or nil expected, got " .. type(damage)
		end
		return true, {kind = "stack", value = {name = name, damage = damage}}
	else
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
		local ok, v = processItem(v)
		if not ok then
			error("Config entry " .. tostring(k) .. newV)
		end
		newRegistry[k] = v
	end
	for k in pairs(registry) do
		registry[k] = nil
	end
	for k, v in pairs(newRegistry) do
		registry[k] = v
	end
	return true
end

local function populateStacks(stackArray, node)
	if node.kind == "stack" then
		table.insert(stackArray, node.value)
	end
end

local function lookupStacks(name)
	local entry = registry[name]
	if not entry then
		return nil
	end
	local result = {}
	populateStacks(result, entry)
	return result
end

return {
	registry = registry,
	reload = reload,
	lookupStacks = lookupStacks,
}
