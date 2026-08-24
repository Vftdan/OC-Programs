local serialization = require "serialization"
local thread = require "thread"

local function serializeArgs(...)
	local builder = {"("}
	for i = 1, select("#", ...) do
		local arg = select(i, ...)
		table.insert(builder, serialization.serialize(arg))
		table.insert(builder, ",")
	end
	if #builder > 1 then
		builder[#builder] = ")"
	else
		builder[2] = ")"
	end
	return table.concat(builder)
end

local function deepMatch(value, pattern, visitedMulti)
	if pattern == nil then
		return true
	end
	if type(pattern) == "function" then
		return pattern(value)
	end
	if type(value) ~= type(pattern) then
		return false
	end
	if type(pattern) == "table" then
		local visited = visitedMulti[pattern]
		if not visited then
			visited = {}
			visitedMulti[pattern] = visited
		end
		if visited[value] then
			return true
		end
		visited[value] = true
		for k, v in pairs(pattern) do
			if not deepMatch(value[k], v) then
				return false
			end
		end
		return true
	else
		return value == pattern
	end
end

local function matchItemSpec(stack, specifiers)
	assert(type(specifiers) == "table")
	return deepMatch(stack, specifiers, {})
end

local function runParallel(f, lst, ...)
	local n = lst.n or #lst
	local threads = {}
	local hasError = false
	local errorMessage
	local results = {n = n}
	local function wrapper(i, ...)
		local success, value = pcall(f, ...)
		if success then
			results[i] = value
		else
			hasError = true
			errorMessage = value
		end
	end
	for i = 1, n do
		threads[i] = thread.create(wrapper, i, lst[i], ...)
	end
	thread.waitForAll(threads)
	if hasError then
		error(errorMessage)
	end
	return results
end

return {
	serializeArgs = serializeArgs,
	matchItemSpec = matchItemSpec,
	runParallel = runParallel,
}
