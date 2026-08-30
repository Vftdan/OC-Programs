local lazytable = require "recipesched.lazytable"

local meta = {}
meta.__index = meta

local descrs = lazytable.create(function(nsName)
	local forMod
	forMod = lazytable.create(function(kindName)
		local known, handlers = pcall(require, ("recipesched.reskind.%s.%s"):format(nsName, kindName))
		return setmetatable({
			_container = forMod,
			nsName = nsName,
			kindName = kindName,
			known = known,
			handlers = handlers,
		}, meta)
	end, {weak = true})
	return forMod
end, {weak = true})

local symbolToDescr = setmetatable({}, {__mode = "k"})

local symbols = lazytable.create(function(nsName)
	local forMod
	forMod = lazytable.create(function(kindName)
		local descr = descrs[nsName][kindName]
		local kindSym = lazytable.create(function(instName)
			return function(fields)
				return descr:makeConfigInstance(instName, fields)
			end
		end, {frozen = true, weak = true, toString = function() return ("kind[%q][%q]"):format(nsName, kindName) end})
		symbolToDescr[kindSym] = descr
		return kindSym
	end, {frozen = true, weak = true, toString = function() return ("kind[%q]"):format(nsName) end})
	return forMod
end, {frozen = true, weak = true, toString = function() return "kind" end})

function meta:getResPair()
	return {
		ns = self.nsName,
		kind = self.kindName,
	}
end

function meta:makeConfigInstance(instName, fields)
	fields = fields or {}
	local value = {name = instName}
	local populateFields = self.handlers and self.handlers.populateFields
	if populateFields then
		populateFields(value, fields)
	end
	return {
		kind = "stack",
		res = self:getResPair(),
		value = value,
	}
end

function meta:finalizeValue(origValue)
	local cb = self.handlers and self.handlers.finalizeValue
	if cb then
		return cb(origValue)
	end
	local name = origValue.name
	if type(name) ~= "string" then
		return false, ".name: string expected, got " .. type(name)
	end
	return true, {
		name = name,
	}
end

function meta:getSpecifiers(value)
	local cb = self.handlers and self.handlers.getSpecifiers
	if cb then
		return cb(value)
	end
	return {
		name = value.name,
	}
end

function meta:setAmount(spec, amount)
	local cb = self.handlers and self.handlers.setAmount
	if cb then
		return cb(spec, amount)
	end
end

function meta:matches(itemDescr)
	if type(itemDescr) ~= "table" then
		return false
	end
	if itemDescr.kind ~= "stack" then
		return false
	end
	local res = itemDescr.res
	if type(res) ~= "table" then
		return false
	end
	if res.ns ~= self.nsName then
		return false
	end
	if res.kind ~= self.kindName then
		return false
	end
	return true
end

function meta:__tostring()
	return ("reskinds.descrs[%q][%q]"):format(self.nsName, self.kindName)
end

local function fromResPair(resource)
	if not resource then
		return nil
	end
	local nsName = resource.ns
	local kindName = resource.kind
	local kindDescr = descrs[nsName][kindName]
	return kindDescr
end

local function fromInstance(itemDescr)
	assert(itemDescr.kind == "stack")
	return fromResPair(itemDescr.res)
end

return {
	descrs = descrs,
	symbols = symbols,
	symbolToDescr = symbolToDescr,
	fromResPair = fromResPair,
	fromInstance = fromInstance,
}
