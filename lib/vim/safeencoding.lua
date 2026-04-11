local sysencoding = require("vim.platform.sysencoding")

-- Treat invalid code units as special code points

local function len(s)
	local result = 0
	while true do
		local inv = sysencoding.firstInvalidByte(s)
		if not inv then
			return result + sysencoding.len(s)
		end
		result = result + sysencoding.len(s:sub(1, inv - 1)) + 1
		s = s:sub(inv + 1)
	end
end

local function sub(s, start, stop)
	local n = len(s)
	start = start or 1
	stop = stop or n
	if start < 0 then
		start = start + n + 1
		if start < 0 then
			start = 0
		end
	end
	if stop < 0 then
		stop = stop + n + 1
		if stop < 0 then
			stop = 0
		end
	end
	if stop < start then
		return ""
	end
	local prefix = ""
	while true do
		local inv = sysencoding.firstInvalidByte(s)
		if not inv then
			return prefix .. sysencoding.sub(s, start, stop)
		end
		local validChunk = s:sub(1, inv - 1)
		local invalidByte = s:sub(inv, inv)
		s = s:sub(inv + 1)
		local validChunkLen = sysencoding.len(validChunk)
		if stop <= validChunkLen then
			return prefix .. sysencoding.sub(validChunk, start, stop)
		elseif stop == validChunkLen + 1 then
			return prefix .. sysencoding.sub(validChunk, start) .. invalidByte
		end
		if start == validChunkLen + 1 then
			prefix = prefix .. invalidByte
		elseif start <= validChunkLen then
			prefix = prefix .. sysencoding.sub(validChunk, start) .. invalidByte
		end
		start = start - validChunkLen - 1
		stop = stop - validChunkLen - 1
		if start < 1 then
			start = 1
		end
	end
end

local function findAllInvalidCodePoints(s)
	local offset = 0
	local result = {}
	while true do
		local inv = sysencoding.firstInvalidByte(s)
		if not inv then
			return result
		end
		local validChunkLen = sysencoding.len(s:sub(1, inv - 1))
		offset = offset + validChunkLen + 1
		local m = {offset, offset}
		table.insert(result, m)
		s = s:sub(inv + 1)
	end
end

local function getCodePointOrUnitCode(ch)
	local valid, code = pcall(sysencoding.codePointAt, ch, 1)
	if valid and type(code) == "number" then
		return true, code
	end
	code = ch:byte(1) or 0
	return false, code
end

return {
	len = len,
	sub = sub,
	findAllInvalidCodePoints = findAllInvalidCodePoints,
	getCodePointOrUnitCode = getCodePointOrUnitCode,
}
