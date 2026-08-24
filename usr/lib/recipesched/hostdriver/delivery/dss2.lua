local hasLz16, lz16 = pcall(require, "liblz16")
local serial = require "serialization"
local util = require "recipesched.util"
local os = require "os"
local buffer = require "buffer"
local minitel = require "minitel"

--[[
-- Criteria is a table with string keys and primitive (i. e. non-reference typed) values
-- compress: boolean -- wrap response in an lz16 stream
-- fuzzy: boolean -- strings are checked against case-insensitive inclusion instead of case-sensitive equality
-- (anything else): number | (string & Preim(tonumber, nil)) -- item specifier fields
--]]
local function serializeMatchHeader(criteria)
	local builder = {}
	for k, v in pairs(criteria) do
		table.insert(builder, ("%s=%s"):format(k, v))
	end
	return table.concat(builder, "\t") .. "\n"
end

local function itemSpecCriteria(spec)
	local criteria = {fuzzy = false, compress = hasLz16}
	for k, v in pairs(spec) do
		local accept = true
		accept = accept and criteria[k] == nil
		if accept then
			local t = type(v)
			if t == "number" then
				-- ok
			elseif t == "string" then
				accept = not tonumber(v)
			else
				accept = false
			end
		end
		if accept then
			criteria[k] = v
		end
	end
	return criteria
end

local function noop()
end

local function hostMatchAll(host, port, spec)
	local criteria = itemSpecCriteria(spec)
	if host == "localhost" then
		local inv = require "inv"
		local fuzzy = criteria.fuzzy
		criteria.fuzzy = nil
		criteria.compress = nil
		local stacks = inv.matchAll(criteria, fuzzy)
		return stacks
	end
	local conn, reason = minitel.open(host, port)
	if not conn then
		error(("Could not connect to %s:%d: %s"):format(host, port, tostring(reason)))
	end
	conn:write(serializeMatchHeader(criteria))
	conn.mode = {r = true}
	local function readChunk()
		if conn.state ~= "open" then
			return nil
		end
		os.sleep(0.05)
		return conn:read("*a")
	end
	local reader = buffer.new("rb", {read = readChunk, close = noop})
	if criteria.compress then
		reader = lz16.buffer(reader)
	end
	local stacks = {}
	for line in reader:lines() do
		table.insert(stacks, serial.unserialize(line))
	end
	return stacks
end

local function hostCountPresentItems(host, port, names)
	local items = require "recipesched.items"
	-- TODO `forStacks`?
	local result = {}
	for _, name in ipairs(names) do
		local amount = 0
		local specList = items.nameToSpecList(name)
		-- FIXME double counting for intersecting specs
		for _, spec in ipairs(specList) do
			local stacks = hostMatchAll(host, port, spec)
			for _, stack in ipairs(stacks) do
				amount = amount + stack.size
			end
		end
		result[name] = {amount = amount}
	end
	return result
end

local function apiDeliver(api, destination, order)
	local items = require "recipesched.items"
	local recipes = require "recipesched.recipes"

	local destPair = api.getAliases()[destination]
	if not destPair then
		error(("Unknown wired destination: %q"):format(destination))
	end
	for _, entry in ipairs(order) do
		local name = recipes.getRecipeItemName(entry.ref)
		if not name then
			error(("Not an item: %q"):format(entry.ref))
		end
		local specList = items.nameToSpecList(name)
		if #specList == 0 then
			error(("Unpopulated item %q"):format(name))
		end
		-- TODO accept enough information to handle #specList > 1
		local specifications = {
			name = specList[1].name,
			damage = specList[1].damage,
		}
		api.extract(specifications, entry.amount, destPair[1], destPair[2])
	end
end

return require("recipesched.basehostdriver").create({
	features = {delivery = true},
	fallbackFeatures = {stockCount = true},
}, function(hostName)
	local rpc = require "rpc"

	local streamPort = 15
	do
		local portStart = hostName:find(":%d+$")
		if portStart then
			streamPort = assert(tonumber(hostName:sub(portStart + 1)))
			hostName = hostName:sub(1, portStart - 1)
		end
	end

	local api = assert(rpc.proxy(hostName, "inv_"), ("Could not create RPC proxy for %q"):format(hostName))

	local function deliver(destination, order)
		return apiDeliver(api, destination, order)
	end

	local function countPresentItems(names)
		return hostCountPresentItems(hostName, streamPort, names)
	end

	return {
		deliver = deliver,
		countPresentItems = countPresentItems,
	}
end)
