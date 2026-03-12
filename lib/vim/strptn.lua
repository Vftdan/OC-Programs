local safeencoding = require("vim.safeencoding")
local itertools = require("vim.itertools")
local math = require("math")

local KEYWORD_PTN = "[%w_\x80-\xff]+"
local PUNCT_PTN = "[^%s%w_\x80-\xff]+"
local NONSPACE_PTN = "%S+"
local SPACE_PTN = "%s+"
local BACKSLASH = "\\"
local BACKSLASH_OR_SPACE_PTN = "[%s\\]"
local NON_AL_BANG_PTN = "[^%a!\x80-\xff]"
local GLOB_CHAR_PTN = "[%*%?]"
local MAGIC_CHARS = "().%+-*?[^$"
local MAGIC_CHARS_PTN

local builder = {"["}
for i = 1, #MAGIC_CHARS do
	table.insert(builder, "%" .. MAGIC_CHARS:sub(i, i))
end
builder[#builder + 1] = "]"
MAGIC_CHARS_PTN = table.concat(builder)
builder = nil

local function prependPercent(s)
	return "%" .. s
end

local function escapePtn(s)
	local result = s:gsub(MAGIC_CHARS_PTN, prependPercent)
	return result
end

local function tokenizePtn(s)
	local tokens = {}
	local i = 0
	while i < #s do
		i = i + 1
		local c = s:sub(i, i)
		if c == "%" then
			if i == #s then
				return nil, "trailing %"
			end
			i = i + 1
			c = c .. s:sub(i, i)
		end
		if c == "%b" then
			if i >= #s - 1 then
				return nil, "unfinished balanced rule"
			end
			i = i + 2
			c = c .. s:sub(i - 1, i)
		end
		table.insert(tokens, c)
	end
	return tokens
end

-- Lua engine is more lenient and may treat misplaced tokens as if they were escaped
-- We will reject it as potentially not what the user intends to express
local function validatePtn(ptn)
	local tokens, reason = tokenizePtn(ptn)
	if not tokens then
		return false, reason
	end
	local insideSet = false
	local setStart = false
	local groupDepth = 0
	local allowQuantifiers = false
	for _, tok in ipairs(tokens) do
		if tok == "(" then
			if insideSet then
				return false, "capture inside set"
			end
			groupDepth = groupDepth + 1
			allowQuantifiers = false
		elseif tok == ")" then
			if insideSet then
				return false, "capture ending inside set"
			end
			if groupDepth < 1 then
				return false, "unmatched capture ending"
			end
			groupDepth = groupDepth - 1
			allowQuantifiers = false
		elseif tok == "+" or tok == "-" or tok == "*" or tok == "?" then
			if not allowQuantifiers then
				return false, "misplaced quantifier"
			end
			allowQuantifiers = false
		elseif tok == "[" then
			if insideSet then
				return false, "nested set"
			end
			insideSet = true
			allowQuantifiers = false
		elseif tok == "]" then
			-- When not inside set, it is treated literally
			insideSet = false
			allowQuantifiers = true
		elseif tok == "^" then
			if insideSet and not setStart then
				return false, "set negation not in the beginning"
			end
			allowQuantifiers = false
		elseif tok == "$" then
			if insideSet then
				return false, "eos rule inside set"
			end
			allowQuantifiers = false
		elseif tok:sub(1, 2) == "%b" then
			allowQuantifiers = false
		else
			-- Literal and escaped characters, classes, universal class
			allowQuantifiers = true
		end
		setStart = tok == "["
	end
	if groupDepth > 0 then
		return false, "unterminated capture"
	end
	if insideSet then
		return false, "unterminated set"
	end
	return true
end

local function byteLengthBetween(s, i, j)
	return #safeencoding.sub(s, i, j)
end

local function unitPointIndex(s, unitIndex)
	local len = safeencoding.len(s)
	if unitIndex > #s then
		return len + 1
	end
	local lower = 1
	local higher = unitIndex
	local guess = higher
	while lower < higher do
		local firstUnit = byteLengthBetween(s, 1, guess - 1) + 1
		local lastUnit = byteLengthBetween(s, 1, guess)
		if firstUnit > unitIndex then
			if higher == guess then
				higher = higher - 1
			else
				higher = guess
			end
			guess = math.floor((guess + lower) / 2)
		elseif lastUnit < unitIndex then
			if lower == guess then
				lower = lower + 1
			else
				lower = guess
			end
			guess = math.ceil((guess + higher) / 2)
		else
			return guess
		end
	end
	return higher
end

local function findAll(haystack, needle, opts)
	opts = opts or {}
	if not opts.pattern then
		needle = escapePtn(needle)
	end
	local start = opts.start or 1
	if not opts.bytes then
		start = byteLengthBetween(haystack, 1, start - 1) + 1
	end
	local result = {}
	while true do
		local m = {haystack:find(needle, start)}
		if not m[1] then
			break
		end
		table.insert(result, m)
		if opts.overlap or m[1] > m[2] then
			start = m[1] + 1
		else
			start = m[2] + 1
		end
	end
	if not opts.bytes then
		for _, m in ipairs(result) do
			m[1] = unitPointIndex(haystack, m[1])
			m[2] = unitPointIndex(haystack, m[2])
		end
	end
	return result
end

local function findWordBoundaries(haystack, opts)
	opts = opts or {}
	local start = opts.start or 1
	if not opts.bytes then
		start = byteLengthBetween(haystack, 1, start - 1) + 1
	end
	local result = {}
	local matches = {
		keyword = {haystack:find(KEYWORD_PTN, start)},
		punct = {haystack:find(PUNCT_PTN, start)},
	}
	while matches.keyword[1] or matches.punct[1] do
		local m
		local punctStart = matches.punct[1]
		local keywordStart = matches.keyword[1]
		if not punctStart or keywordStart and keywordStart < punctStart then
			m = matches.keyword
			m.isPunct = false
			start = m[2] + 1
			matches.keyword = {haystack:find(KEYWORD_PTN, start)}
		else
			m = matches.punct
			m.isPunct = true
			start = m[2] + 1
			matches.punct = {haystack:find(PUNCT_PTN, start)}
		end
		table.insert(result, m)
	end
	if not opts.bytes then
		for _, m in ipairs(result) do
			m[1] = unitPointIndex(haystack, m[1])
			m[2] = unitPointIndex(haystack, m[2])
		end
	end
	return result
end

local function findNonSpaceBoundaries(haystack, opts)
	opts = opts or {}
	local start = opts.start or 1
	if not opts.bytes then
		start = byteLengthBetween(haystack, 1, start - 1) + 1
	end
	local result = {}
	while true do
		local m = {haystack:find(NONSPACE_PTN, start)}
		if not m[1] then
			break
		end
		table.insert(result, m)
		start = m[2] + 1
	end
	if not opts.bytes then
		for _, m in ipairs(result) do
			m[1] = unitPointIndex(haystack, m[1])
			m[2] = unitPointIndex(haystack, m[2])
		end
	end
	return result
end

local function matchesGetAdjacent(matches, target, key, opts)
	opts = opts or {}
	local backward = opts.backward or false
	local count = opts.count or 1
	key = key or 1
	local lower = 1
	local higher = #matches
	if higher < 1 then
		return nil, count
	end
	local guess = math.floor((lower + higher) / 2)
	while lower < higher do
		local m = matches[guess]
		if m[key] == target then
			break
		end
		if m[key] < target then
			if lower == guess then
				lower = lower + 1
			else
				lower = guess
			end
			guess = math.ceil((guess + higher) / 2)
		else
			if higher == guess then
				higher = higher - 1
			else
				higher = guess
			end
			guess = math.floor((guess + lower) / 2)
		end
	end
	local m = matches[guess]
	if backward then
		if m[key] >= target then
			guess = guess - 1
		end
		guess = guess - count + 1
		if guess < 1 then
			return nil, 1 - guess
		end
	else
		if m[key] <= target then
			guess = guess + 1
		end
		guess = guess + count - 1
		if guess > #matches then
			return nil, guess - #matches
		end
	end
	return matches[guess], 0
end

local function matchesGetContainingIndex(matches, target)
	local lower = 1
	local higher = #matches
	if higher < 1 then
		return 0
	end
	if matches[lower][1] > target then
		return 0
	end
	if matches[higher][2] < target then
		return higher + 1
	end
	local guess = math.floor((lower + higher) / 2)
	while lower < higher do
		local m = matches[guess]
		local beginsNotAfter = m[1] <= target
		local endsNotBefore = m[2] >= target
		if beginsNotAfter and endsNotBefore then
			break
		end
		if beginsNotAfter then
			if lower == guess then
				lower = lower + 1
			else
				lower = guess
			end
			guess = math.ceil((guess + higher) / 2)
		else
			if higher == guess then
				higher = higher - 1
			else
				higher = guess
			end
			guess = math.floor((guess + lower) / 2)
		end
	end
	return guess
end

local function matchesMerge(matchesTable, compareKey, selectKey)
	compareKey = compareKey or 1
	if selectKey then
		matchesTable = itertools.collect(pairs(matchesTable))
		for selectValue, matches in pairs(matchesTable) do
			matchesTable[selectValue] = itertools.collect(itertools.mapIterator(function(i, m)
				m = itertools.collect(pairs(m))
				m[selectKey] = selectValue
				return i, m
			end, ipairs(matches)))
		end
	end
	local positions = {}
	for selectValue in pairs(matchesTable) do
		positions[selectValue] = 1
	end
	local result = {}
	while true do
		local minSelectValue = nil
		local minM = nil
		for selectValue, matches in pairs(matchesTable) do
			local m = matches[positions[selectValue]]
			if m and m[compareKey] then
				assert(m[selectKey] == selectValue)
				if not minM or m[compareKey] < minM[compareKey] then
					minSelectValue = selectValue
					minM = m
				end
			end
		end
		if not minM then
			return result
		end
		table.insert(result, minM)
		positions[minSelectValue] = positions[minSelectValue] + 1
	end
end

local function firstNonSpace(haystack)
	local i = haystack:find(NONSPACE_PTN)
	return i
end

local function firstSpace(haystack)
	local i = haystack:find(SPACE_PTN)
	if not i then
		return nil
	end
	return unitPointIndex(haystack, i)
end

local function firstNonAlBang(haystack)
	local i = haystack:find(NON_AL_BANG_PTN)
	if not i then
		return nil
	end
	return unitPointIndex(haystack, i)
end

local function firstBackslash(haystack)
	local i = haystack:find(BACKSLASH)
	if not i then
		return nil
	end
	return unitPointIndex(haystack, i)
end

local function firstUnescapedSpace(haystack)
	local start = 1
	while start <= #haystack do
		local i = haystack:find(BACKSLASH_OR_SPACE_PTN, start)
		if not i then
			return nil
		end
		local ch = haystack:sub(i, i)
		if ch == BACKSLASH then
			start = i + 2
		else
			return unitPointIndex(haystack, i)
		end
	end
	return nil
end

local function unescapeBackslash(haystack)
	local builder = {}
	local start = 1
	-- TODO hex sequences
	while start <= #haystack do
		local i = haystack:find(BACKSLASH, start)
		if not i then
			break
		end
		local ch = haystack:sub(i + 1, i + 1)
		table.insert(builder, ch)
		start = i + 2
	end
	if start <= #haystack then
		table.insert(builder, haystack:sub(start))
	end
	return table.concat(builder)
end

local splitBy = function(haystack, needle, opts)
	opts = opts or {}
	if not opts.pattern then
		needle = escapePtn(needle)
	end
	local start = 1
	local result = {}
	while start <= #haystack + 1 do
		local sepStart, sepEnd = haystack:find(needle, start)
		if not sepStart then
			table.insert(result, haystack:sub(start))
			break
		end
		table.insert(result, haystack:sub(start, sepStart - 1))
		start = sepEnd + 1
	end
	return result
end

local function fromGlob(gl)
	-- TODO square brackets
	local start = 1
	local builder = {}
	while start <= #gl do
		local i = gl:find(GLOB_CHAR_PTN, start)
		if not i then
			break
		end
		table.insert(builder, escapePtn(gl:sub(start, i - 1)))
		local ch = gl:sub(i, i)
		if ch == "?" then
			table.insert(builder, ".")
		else
			table.insert(builder, ".*")
		end
		start = i + 1
	end
	table.insert(builder, escapePtn(gl:sub(start)))
	return table.concat(builder)
end

return {
	escapePtn = escapePtn,
	validatePtn = validatePtn,
	unitPointIndex = unitPointIndex,
	findAll = findAll,
	findWordBoundaries = findWordBoundaries,
	findNonSpaceBoundaries = findNonSpaceBoundaries,
	matchesGetAdjacent = matchesGetAdjacent,
	matchesGetContainingIndex = matchesGetContainingIndex,
	matchesMerge = matchesMerge,
	firstNonSpace = firstNonSpace,
	firstSpace = firstSpace,
	firstNonAlBang = firstNonAlBang,
	firstBackslash = firstBackslash,
	firstUnescapedSpace = firstUnescapedSpace,
	unescapeBackslash = unescapeBackslash,
	splitBy = splitBy,
	fromGlob = fromGlob,
}
