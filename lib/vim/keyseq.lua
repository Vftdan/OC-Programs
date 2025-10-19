-- RegExp: /^\<(\w+\-)*(\w+|.)\>/
local function findValidKeyAt(s, pos)
	local pre = s:match("^%<[%w%-]*.%>", pos)
	if pre == nil then
		return nil
	end
	local i = 0
	local afterAlnum = false
	local expectEnd = false
	for c in pre:gmatch(".") do
		i = i + 1
		if i == 1 then
			-- Already checked
		elseif expectEnd then
			if c == ">" then
				return i + pos - 1
			else
				return nil
			end
		elseif c:find("%w") then
			afterAlnum = true
		elseif afterAlnum then
			if c == "-" then
				afterAlnum = false
			elseif c == ">" then
				return i + pos - 1
			else
				return nil
			end
		else
			expectEnd = true
		end
	end
	return nil
end

local function splitKeySeq(s)
	local ks = {}
	local pos = 1
	while pos <= #s do
		local i = findValidKeyAt(s, pos)
		if i ~= nil then
			ks[#ks + 1] = s:sub(pos + 1, i - 1)
			pos = i + 1
		else
			ks[#ks + 1] = s:sub(pos, pos)
			pos = pos + 1
		end
	end
	return ks
end

local function normalizeKey(key, keyAliases, modOrder)
	local unmodified = key:match("[^-]*.$")
	unmodified = keyAliases[unmodified:lower()] or unmodified
	local mods = {}
	for m in key:gmatch("(.-)%-") do
		mods[m:upper()] = true
	end
	local builder = {}
	for _, m in ipairs(modOrder) do
		m = m:upper()
		if mods[m] then
			table.insert(builder, m .. "-")
		end
	end
	table.insert(builder, unmodified)
	return table.concat(builder)
end

local function parseKeySequence(s, keyAliases, modOrder)
	local parsed = {}
	for i, k in ipairs(splitKeySeq(s)) do
		parsed[i] = normalizeKey(k, keyAliases, modOrder)
	end
	return parsed
end

local function stringifyKeySequence(seq)
	local builder = {}
	for _, k in ipairs(seq) do
		if k == "<" then
			k = "<lt>"  -- As a safeguard, should be unreachable
		elseif #k > 1 then
			k = "<" .. k .. ">"
		end
		table.insert(builder, k)
	end
	return table.concat(builder)
end

return {
	normalizeKey = normalizeKey,
	parseKeySequence = parseKeySequence,
	stringifyKeySequence = stringifyKeySequence,
}
