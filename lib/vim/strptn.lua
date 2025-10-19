local sysencoding = require("vim.platform.sysencoding")
local math = require("math")

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
	return s:gsub(MAGIC_CHARS_PTN, prependPercent)
end

local function byteLengthBetween(s, i, j)
	return #sysencoding.sub(s, i, j)
end

local function unitPointIndex(s, unitIndex)
	local len = sysencoding.len(s)
	if unitIndex > #s then
		return len + 1
	end
	local lower = unitIndex
	local higher = len
	local guess = lower
	while lower < higher do
		local firstUnit = byteLengthBetween(s, 1, lower - 1) + 1
		local lastUnit = byteLengthBetween(s, 1, lower)
		if firstUnit > unitIndex then
			higher = guess
			guess = math.floor((guess + lower) / 2)
		elseif lastUnit < unitIndex then
			lower = guess
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
		if opts.overlap then
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

return {
	escapePtn = escapePtn,
	findAll = findAll,
}
