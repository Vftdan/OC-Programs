local event = require("event")
local keyboard = require("keyboard")
local unicode = require("unicode")

local mouseButtonNames = {
	[0] = "left",
	[1] = "right",
	[2] = "middle",
}

local keyNames = {}

for name, code in pairs(keyboard.keys) do
	keyNames[code] = name
end

local function pullNative()
	return table.pack(event.pull())
end

local function pullNativeTimeout(to)
	local ev = table.pack(event.pull(to))
	if not ev[1] then
		return nil
	end
	return ev
end

local function isTerminalResize(native)
	if native[1] == "screen_resized" then
		return true, {
			screenId = native[2],
			width = native[3],
			height = native[4],
		}
	end
	return false
end

local function isMouseDown(native)
	if native[1] == "touch" then
		return true, {
			screenId = native[2],
			x = native[3],
			y = native[4],
			button = native[5],
		}
	end
	return false
end

local function isMouseDrag(native)
	if native[1] == "drag" then
		return true, {
			screenId = native[2],
			x = native[3],
			y = native[4],
			button = native[5],
		}
	end
	return false
end

local function isMouseUp(native)
	if native[1] == "drop" then
		return true, {
			screenId = native[2],
			x = native[3],
			y = native[4],
			button = native[5],
		}
	end
	return false
end

local function isMouseScroll(native)
	if native[1] == "scroll" then
		return true, {
			screenId = native[2],
			-- pointer position:
			x = native[3],
			y = native[4],
			-- scroll amount (positive is down and right)
			dx = 0,
			dy = -native[5],
		}
	end
	return false
end

local function isKeyPressOrChar(native)
	if native[1] == "key_down" then
		local symbolCode = native[3]
		local printable = true
		if symbolCode < 1 then
			symbolCode = nil
			printable = false
		elseif symbolCode < 32 or symbolCode == 127 then
			printable = false  -- handle line feed and tabulation separately
		end
		local text = nil
		if printable then
			text = unicode.char(symbolCode)
		end
		return true, {
			keyboardId = native[2],
			symbolCode = symbolCode,
			scanCode = native[4],
			held = nil,  -- not supported in OC
			printable = printable,
			text = text,
		}
	end
	return false
end

local function isKeyUp(native)
	if native[1] == "key_up" then
		return true, {
			keyboardId = native[2],
			scanCode = native[4],
		}
	end
	return false
end

local function isPaste(native)
	if native[1] == "clipboard" then
		return true, {
			keyboardId = native[2],
			text = native[3],
			consumedEvent = nil,
		}
	end
	return false
end

local function isInterrupt(native)
	if native[1] == "interrupted" then
		return true, {
		}
	end
	return false
end

return {
	mouseButtonNames = mouseButtonNames,
	keyNames = keyNames,
	keyScanCodes = keyboard.keys,
	pasteKey = "insert",
	pullNative = pullNative,
	pullNativeTimeout = pullNativeTimeout,
	isTerminalResize = isTerminalResize,
	isMouseDown = isMouseDown,
	isMouseDrag = isMouseDrag,
	isMouseUp = isMouseUp,
	isMouseScroll = isMouseScroll,
	isKeyPressOrChar = isKeyPressOrChar,
	isKeyUp = isKeyUp,
	isPaste = isPaste,
	isInterrupt = isInterrupt,
}
