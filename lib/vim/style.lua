local itertools = require("vim.itertools")
local makeClass = require("vim.makeclass")
local defaultstyle = require("vim.defaultstyle")

local StyleRegistry = makeClass {
	init = function(self)
		self._definitions = {}
		self._links = {}
	end,
	define = function(self, name, tbl)
		name = name:lower()
		self._links[name] = nil
		self._definitions[name] = tbl
	end,
	link = function(self, alias, actual)
		alias = alias:lower()
		actual = actual:lower()
		self._links[alias] = actual
		self._definitions[alias] = nil
	end,
	defineDefault = function(self, name, tbl)
		name = name:lower()
		if self._links[name] or self._definitions[name] then
			return
		end
		self:define(name, tbl)
	end,
	linkDefault = function(self, alias, actual)
		alias = alias:lower()
		if self._links[alias] or self._definitions[alias] then
			return
		end
		self:link(alias, actual)
	end,
	resolve = function(self, name)
		local visited = {}
		name = name:lower()
		while true do
			if name == nil or visited[name] then
				return nil
			end
			visited[name] = true
			local tbl = self._definitions[name]
			if tbl then
				return tbl
			end
			name = self._links[name]
		end
	end,
	resolveStack = function(self, names)
		local result = {reverse = false}
		for _, name in ipairs(names) do
			local tbl = self:resolve(name)
			if tbl then
				local reverse = result.reverse
				if tbl.reverse then
					reverse = not reverse
				end
				itertools.update(result, tbl)
				result.reverse = reverse
			end
		end
		return result
	end,
}

local function makeDefault()
	local registry = StyleRegistry()
	for k, v in pairs(defaultstyle.mapping) do
		if type(v) == "string" then
			registry:linkDefault(k, v)
		else
			registry:defineDefault(k, v)
		end
	end
	return registry
end

return {
	makeDefault = makeDefault,
	StyleRegistry = StyleRegistry,
}
