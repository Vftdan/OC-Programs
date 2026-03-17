local makeClass = require("vim.makeclass")
local typeahead = require("vim.typeahead")
local style = require("vim.style")
local helpers = require("vim.helpers")
local safeencoding = require("vim.safeencoding")
local modeacts = require("vim.modeacts")
local modes = require("vim.modes")
local textrender = require("vim.platform.textrender")
local itertools = require("vim.itertools")
local Trie = require("vim.trie")
local window = require("vim.window")
local autocmd = require("vim.autocmd")

local Editor = makeClass {
	init = function(self)
		self._running = true
		self._interruptRaising = false
		self._interruptOptions = true
		self._buffers = {n = 0}
		self._windows = {n = 0}
		self._activeWinId = 0
		self.styleRegistry = style.makeDefault()
		self.modeTries = {}
		self.mappings = {}
		self.typeahead = typeahead.Typeahead()
		modeacts.initialize(self.modeTries)
		self._scrollOption = 10
		self._modeMessage = nil
		self.typeahead:addPreWaitHandler(function() self:render() end)
		self.typeahead.onSoftInterrupt = function()
			self:raiseSoftInterrupt{message = "Interrupted, type :q! and press <enter> to abandon all changes and exit"}
		end
		self._interpretedStyleStacks = Trie()
		self._cmdlineRunning = false
		self._cmdlineCursor = nil
		self._cmdlineMessage = nil
		self.hlsearch = false
		self.triggerHlsearch = false
		self.commandHistory = {}
		self.searchHistory = {}
		self.runtimeDirs = {"/etc/vimruntime", "/usr/etc/vimruntime", "/home/.vim"}
		self.enableSyntax = false
		self.autocmdRegistry = autocmd.AutocmdRegistry(self)
		self.statusLineFormatString = ""
	end,
	isRunning = function(self)
		return self._running
	end,
	terminate = function(self)
		self._running = false
		self.typeahead:terminate()
	end,
	notInterrupted = function(self)
		return self._running and not self._interruptRaising
	end,
	raiseSoftInterrupt = function(self, opts)
		opts = opts or {}
		self._interruptRaising = true
		self._interruptOptions = opts
	end,
	clearSoftInterrupt = function(self)
		self.typeahead:clearInterrupt()
		self._interruptRaising = false
		self._interruptOptions = nil
	end,
	registerBuffer = function(self, buf)
		buf:setEditor(self)
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
		local win = self:getCurrentWindow()
		if win then
			win:setFocused(false)
		end
		if id >= 0 and id <= self._windows.n then
			self._activeWinId = id
		end
		win = self:getCurrentWindow()
		if win then
			win:setFocused(true)
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
			self.typeahead:clearInterrupt()
			if self._interruptRaising then
				local opts = self._interruptOptions
				self._interruptRaising = false
				self._interruptOptions = nil
				self.typeahead:clear()
				if opts.messageTable then
					self:echoErr(table.unpack(opts.messageTable, a, opts.messageTable.n))
				elseif opts.message then
					self:echoErr(opts.message)
				end
			end
		end
	end,
	invalidateDisplay = function(self)
		for _, win in ipairs(self._windows) do
			win:invalidateDisplay()
		end
	end,
	render = function(self)
		if not self._windows[1] then
			self:terminate()
			return
		end
		self._windows[1]:render()
		self:renderMessageArea()
	end,
	renderMessageArea = function(self)
		if self._cmdlineRunning then
			local s = self._cmdlineMessage or ""
			local width, height = textrender.getTermSize()
			local psl = window.toPrintableStyled(s)
			psl = window.printableStyledToView(psl, 0, width)
			for _, entry in ipairs(psl) do
				local newStyle = itertools.collect(ipairs(entry.styleNames))
				table.insert(newStyle, 2, "msgarea")
				entry.styleNames = newStyle
			end
			if self._cmdlineCursor then
				psl = window.printableStyledAddCursor(psl, self._cmdlineCursor, "cursor")
			end
			local blitData = {}
			for _, entry in ipairs(psl) do
				local chunk = {entry.string}
				local style = self:interpretStyleStack(entry.styleNames)
				itertools.update(chunk, style)
				table.insert(blitData, chunk)
			end
			textrender.setCursorPos(1, height)
			textrender.blitAll(blitData)
			return
		end
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
			local rightOffset = safeencoding.len(ta)
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
			ta = safeencoding.sub(ta, 1, width - taStart + 1)
			mode = safeencoding.sub(mode, 1, taStart - 1)
			local sepLength = taStart - 1 - safeencoding.len(mode)
			local sep = ""
			if sepLength > 0 then
				sep = itertools.repeatString(" ", sepLength)
			end
			local rightPadLength = width - taStart + 1 - safeencoding.len(ta)
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
	setCmdlineRunning = function(self, flag)
		local win = self:getCurrentWindow()
		if win then
			win:setFocused(not flag)
		end
		self._cmdlineRunning = flag
	end,
	isCmdlineRunning = function(self)
		return self._running and self._cmdlineRunning
	end,
	setCmdlineCursor = function(self, x)
		self._cmdlineCursor = x
	end,
	setCmdlineMessage = function(self, msg)
		self._cmdlineMessage = msg
	end,
	echoStyled = function(self, psl)
		local width, height = textrender.getTermSize()
		psl = window.printableStyledToView(psl, 0, width)
		for _, entry in ipairs(psl) do
			local newStyle = itertools.collect(ipairs(entry.styleNames))
			local i = 1
			if #newStyle and newStyle[1]:lower() == "normal" then
				i = 2
			end
			table.insert(newStyle, i, "msgarea")
			entry.styleNames = newStyle
		end
		local blitData = {}
		for _, entry in ipairs(psl) do
			local chunk = {entry.string}
			local style = self:interpretStyleStack(entry.styleNames)
			itertools.update(chunk, style)
			table.insert(blitData, chunk)
		end
		textrender.setCursorPos(1, height)
		textrender.blitAll(blitData)
	end,
	echo = function(self, ...)
		local args = table.pack(...)
		local builder = {}
		for i = 1, args.n do
			builder[i] = tostring(args[i])
		end
		local s = table.concat(builder, " ")
		local psl = window.toPrintableStyled(s)
		self:echoStyled(psl)
	end,
	echoErr = function(self, ...)
		local args = table.pack(...)
		local builder = {}
		for i = 1, args.n do
			builder[i] = tostring(args[i])
		end
		local s = table.concat(builder, " ")
		local psl = window.toPrintableStyled(s)
		for _, entry in ipairs(psl) do
			local newStyle = itertools.collect(ipairs(entry.styleNames))
			table.insert(newStyle, 2, "errormsg")
			entry.styleNames = newStyle
		end
		self:echoStyled(psl)
	end,
}

return {
	Editor = Editor,
}
