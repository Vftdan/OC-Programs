local makeClass = require("vim.makeclass")
local typeahead = require("vim.typeahead")
local style = require("vim.style")
local helpers = require("vim.helpers")
local sysencoding = require("vim.platform.sysencoding")
local modeacts = require("vim.modeacts")
local modes = require("vim.modes")
local textrender = require("vim.platform.textrender")
local itertools = require("vim.itertools")

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
		self._modeMessage = nil
		self.typeahead:addPreWaitHandler(function() self:render() end)
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
		if mode or #ta > 0 then
			if not mode then
				mode = ""
			end
			local modeMsgStyle = textrender.interpretStyle(self.styleRegistry:resolveStack({"normal", "msgarea", "modemsg"}))
			local typeaheadStyle = textrender.interpretStyle(self.styleRegistry:resolveStack({"normal", "msgarea"}))
			local rightOffset = sysencoding.len(ta)
			if rightOffset < 11 then
				rightOffset = 11
			end
			local width, height = textrender.getTermSize()
			local taStart = width - rightOffset
			if taStart < 1 then
				taStart = 1
			end
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
			local modeChunk = {mode}
			itertools.update(modeChunk, modeMsgStyle)
			local taChunk = {sep .. ta .. rightPad}
			itertools.update(taChunk, typeaheadStyle)
			textrender.setCursorPos(1, height)
			textrender.blitAll{
				modeChunk,
				taChunk,
			}
		end
	end,
}

return {
	Editor = Editor,
}
