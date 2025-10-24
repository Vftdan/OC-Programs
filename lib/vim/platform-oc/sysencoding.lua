local unicode = require("unicode")

local function codePointAt(str, index)
	index = index or 1
	local ch = unicode.sub(str, index, index)
	if #ch < 1 then
		return nil
	end
	local first = ch:byte(1)
	if first < 128 then
		return first
	end
	if first < 192 then
		error("String starts with a continuation code unit")
	end
	local code, numContinutation
	if first < 224 then
		code = first - 192
		numContinutation = 1
	elseif first < 240 then
		code = first - 224
		numContinutation = 2
	elseif first < 248 then
		code = first - 240
		numContinutation = 3
	elseif first < 252 then
		code = first - 248
		numContinutation = 4
	elseif first < 254 then
		code = first - 252
		numContinutation = 5
	else
		error("Invalid leading code unit")
	end
	for i = 2, numContinutation + 1 do
		local cont = ch:byte(i)
		if not ch then
			error("Unexpected end of string")
		end
		if cont < 128 or cont >= 192 then
			error("Not a continuation code unit at offset " .. tostring(i))
		end
		code = code * 64 + (cont - 128)
	end
	return code
end

-- Drop the second return value
local function len(s)
	local n = unicode.len(s)
	return n
end

local function firstInvalidByte(s)
	local _, n = unicode.len(s)
	return n
end

return {
	len = len,
	firstInvalidByte = firstInvalidByte,
	fromCodePoint = unicode.char,
	codePointAt = codePointAt,
	upper = unicode.upper,
	lower = unicode.lower,
	sub = unicode.sub,
}
