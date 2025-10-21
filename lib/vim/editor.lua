local makeClass = require("vim.makeclass")
local typeahead = require("vim.typeahead")
local style = require("vim.style")
local helpers = require("vim.helpers")
local sysencoding = require("vim.platform.sysencoding")
local modeacts = require("vim.modeacts")
local modes = require("vim.modes")
local textrender = require("vim.platform.textrender")
local itertools = require("vim.itertools")
local Trie = require("vim.trie")

local Editor = makeClass {
	init = function(self)
		self._running = true
		self._buffers = {n = 0}
		self._windows = {n = 0}
		self._activeWinId = 0
		self.styleRegistry = style.makeDefault()
		self.modeTries = {}
		self.mappings = {}
		self.typeahead = typeahead.Typeahead()
		modeacts.initialize(self.modeTries)
		-- TODO cursor
		self._cursorX = 1
		self._cursorY = 1
		self._scrollOption = 10
		self._modeMessage = nil
		self.typeahead:addPreWaitHandler(function() self:render() end)
		self._interpretedStyleStacks = Trie()
	end,
	isRunning = function(self)
		return self._running
	end,
	terminate = function(self)
		self._running = false
		self.typeahead:terminate()
	end,
	registerBuffer = function(self, buf)
		local n = self._buffers.n + 1
		self._buffers[n] = buf
		self._buffers.n = n
		return n
	end,
	registerWindow = function(self, win)
		win:setEditor(self)
		local n = self._windows.n + 1
		self._windows[n] = win
		self._windows.n = n
		return n
	end,
	getCurrentWindowId = function(self)
		return self._activeWinId
	end,
	setCurrentWindowId = function(self, id)
		if id >= 0 and id <= self._windows.n then
			self._activeWinId = id
		end
	end,
	getCurrentWindow = function(self)
		if self._activeWinId < 1 then
			return nil
		end
		return self._windows[self._activeWinId]
	end,
	getCurrentBuffer = function(self)
		local win = self:getCurrentWindow()
		if not win then
			return nil
		end
		return win.currentBuffer
	end,
	setModeMessage = function(self, value)
		self._modeMessage = value
	end,
	getModeMessage = function(self)
		return self._modeMessage
	end,
	run = function(self)
		while self._running do
			self:render()
			helpers.runMode(self, modes.normalMode)
		end
	end,
	render = function(self)
		if not self._windows[1] then
			self:terminate()
			return
		end
		self._windows[1]:render()
		local mode = self._modeMessage
		local ta = self.typeahead:stringifyAll()
		local renderMode = mode ~= nil
		local renderTypeahead = ta ~= self._oldTypeaheadString
		if renderMode or renderTypeahead then
			self._oldTypeaheadString = ta
			if not mode then
				mode = ""
			end
			local modeMsgStyle = self:interpretStyleStack{"normal", "msgarea", "modemsg"}
			local typeaheadStyle = self:interpretStyleStack{"normal", "msgarea"}
			local rightOffset = sysencoding.len(ta)
			if rightOffset < 11 then
				rightOffset = 11
			end
			local width, height = textrender.getTermSize()
			local taStart = width - rightOffset
			if taStart < 1 then
				taStart = 1
			end
			local oldTypeaheadStart = self._oldTypeaheadStart or width - 11
			self._oldTypeaheadStart = taStart
			ta = sysencoding.sub(ta, 1, width - taStart + 1)
			mode = sysencoding.sub(mode, 1, taStart - 1)
			local sepLength = taStart - 1 - sysencoding.len(mode)
			local sep = ""
			if sepLength > 0 then
				sep = itertools.repeatString(" ", sepLength)
			end
			local rightPadLength = width - taStart + 1 - sysencoding.len(ta)
			local rightPad = ""
			if rightPadLength > 0 then
				rightPad = itertools.repeatString(" ", rightPadLength)
			end
			local modeChunk = {mode .. sep}
			itertools.update(modeChunk, modeMsgStyle)
			local taChunk = {ta .. rightPad}
			itertools.update(taChunk, typeaheadStyle)
			local blitData = {}
			if renderMode then
				textrender.setCursorPos(1, height)
				blitData[#blitData + 1] = modeChunk
			else
				if oldTypeaheadStart < taStart then
					textrender.setCursorPos(oldTypeaheadStart, height)
					local leftPad = itertools.repeatString(" ", taStart - oldTypeaheadStart)
					taChunk[1] = leftPad .. taChunk[1]
				else
					textrender.setCursorPos(taStart, height)
				end
			end
			if renderTypeahead then
				blitData[#blitData + 1] = taChunk
			end
			textrender.blitAll(blitData)
		end
	end,
	interpretStyleStack = function(self, styleNames)
		local result = self._interpretedStyleStacks:get(styleNames)
		if result == nil then
			result = textrender.interpretStyle(self.styleRegistry:resolveStack(styleNames))
			self._interpretedStyleStacks:put(styleNames, result)
		end
		return result
	end,
}

return {
	Editor = Editor,
}
