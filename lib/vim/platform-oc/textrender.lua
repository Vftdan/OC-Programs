local term = require("term")
local component = require("component")

local defaultPalette = {}
if true then
	local values = {0xA00000, 0x00A000, 0x0000A0, 0x5F5F5F}
	for index = 0, 15 do
		local rgb = 0
		local shifted = index
		for bitPos = 1, 4 do
			if shifted % 2 == 1 then
				shifted = shifted - 1
				rgb = rgb + values[bitPos]
			end
			shifted = shifted / 2
		end
		defaultPalette[index] = rgb
	end
end

local function getGpu()
	return term.gpu and term.gpu() or component.gpu
end

local function getTermSize()
	return getGpu().getResolution()
end

local function getCursorPos()
	return term.getCursor()
end

local function setCursorPos(x, y)
	term.setCursor(x, y)
end

local function blitAll(chunks)
	local gpu = getGpu()
	local oldFg, oldBg = {gpu.getForeground()}, {gpu.getBackground()}
	for _, chunk in ipairs(chunks) do
		local text, fg, bg = table.unpack(chunk)
		gpu.setForeground(fg, not chunk.trueFg)
		gpu.setBackground(bg, not chunk.trueBg)
		term.write(text, false)
	end
	gpu.setForeground(table.unpack(oldFg))
	gpu.setBackground(table.unpack(oldBg))
end

local function enterScreen()
	local oldState = {}
	local gpu = getGpu()
	oldState.fg = {gpu.getForeground()}
	oldState.bg = {gpu.getBackground()}
	local palette = {}
	for i = 1, 16 do
		palette[i] = gpu.getPaletteColor(i - 1)
	end
	oldState.palette = palette
	for index = 0, 15 do
		gpu.setPaletteColor(index, defaultPalette[index])
	end
	gpu.setForeground(15, true)
	gpu.setBackground(0, true)
	term.clear()
	return oldState
end

local function leaveScreen(oldState)
	local gpu = getGpu()
	for i, rgb in ipairs(oldState.palette) do
		gpu.setPaletteColor(i - 1, rgb)
	end
	gpu.setForeground(table.unpack(oldState.fg))
	gpu.setBackground(table.unpack(oldState.bg))
end

local function interpretStyle(tbl)
	local bg = {0, true}
	local fg = {15, true}
	if tbl.guibg then
		bg = {tbl.guibg, false}
	elseif tbl.ctermbg then
		bg = {tbl.ctermbg, true}
	end
	if tbl.guifg then
		fg = {tbl.guifg, false}
	elseif tbl.ctermfg then
		fg = {tbl.ctermfg, true}
	end
	if tbl.reverse then
		bg, fg = fg, bg
	end
	return {[2] = fg[1], [3] = bg[1], trueFg = not fg[2], trueBg = not bg[2]}
end

return {
	getTermSize = getTermSize,
	getCursorPos = getCursorPos,
	setCursorPos = setCursorPos,
	blitAll = blitAll,
	enterScreen = enterScreen,
	leaveScreen = leaveScreen,
	interpretStyle = interpretStyle,
}
