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

local function matches(stack, specifiers)
	assert(type(specifiers) == "table")
	return deepMatch(stack, specifiers, {})
end

return {
	matches = matches,
}
