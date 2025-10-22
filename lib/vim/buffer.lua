local makeClass = require("vim.makeclass")
local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")

local weakMapMeta = {__mode = "k"}
local function weakMap()
	return setmetatable({}, weakMapMeta)
end

local Buffer = makeClass {
	init = function(self)
		self._lines = {""}
		self._cacheRoot = {}
		self._undoList = {{children = {}}, n = 1}
		self._undoIndex = 1
	end,
	setEditor = function(self, editor)
		self._editor = editor
	end,
	_echoInfo = function(self, ...)
		if self._editor then
			self._editor:echo(...)
		end
	end,
	_echoError = function(self, ...)
		if self._editor then
			self._editor:echoErr(...)
		end
	end,
	getLineCount = function(self)
		return #self._lines
	end,
	getLine = function(self, i)
		return self._lines[i]
	end,
	getScopedLineCache = function(self, i, scope)
		if scope == nil then
			return nil
		end
		local lineCache = self._cacheRoot[i]
		if not lineCache then
			return nil
		end
		return lineCache[scope]
	end,
	setScopedLineCache = function(self, i, scope, value)
		if scope == nil then
			return
		end
		local lineCache = self._cacheRoot[i]
		if not lineCache then
			return
		end
		lineCache[scope] = value
	end,
	read = function(self)
		local f = self._filename and io.open(self._filename, "r")
		local lines = {}
		local cacheRoot = {}
		if f ~= nil then
			local line = f:read()
			while line ~= nil do
				lines[#lines + 1] = line
				cacheRoot[#lines] = weakMap()
				line = f:read()
			end
			f:close()
		end
		if #lines < 1 then
			lines[1] = ""
			cacheRoot[1] = weakMap()
		end
		local oldLines = self._lines
		self._lines = lines
		self._cacheRoot = cacheRoot

		local oldStateIndex = self._undoIndex
		local newStateIndex = self._undoList.n + 1
		local oldState = self._undoList[oldStateIndex]
		local childIndex = #oldState.children + 1
		local newState = {parent = oldStateIndex, parentChild = childIndex, x = 1, y = 1, children = {}}
		newState.added = itertools.collect(ipairs(self._lines))
		newState.removed = itertools.collect(ipairs(oldLines))
		oldState.children[childIndex] = newStateIndex
		self._undoList[newStateIndex] = newState
		self._undoList.n = newStateIndex
		self._undoIndex = newStateIndex
	end,
	write = function(self, filename)
		-- TODO writebackup
		filename = filename or self._filename
		if not filename then
			self:_echoError("No file name")
			return
		end
		local f, reason = io.open(filename, "w")
		if f == nil then
			self:_echoError("Failed to open:", reason)
			return
		end
		local success = true
		local numLines = self:getLineCount()
		success, reason = pcall(f.write, f, self:getLine(1))
		for i = 2, numLines do
			if success then
				success, reason = pcall(f.write, f, "\n" .. self:getLine(i))
			else
				break
			end
		end
		if not success then
			self:_echoError("Error while writing:", reason)
			return
		end
		success, reason = pcall(f.close, f)
		if not success then
			self:_echoError("Error while closing:", reason)
			return
		end
		self._echoInfo(string.format("%q %dL written", filename, numLines))
	end,
	--- Copies characterwise lines or their parts into an array
	-- Both beginning and ending characters are included
	-- If the ending is before the beginning, {""} is returned
	-- Out-of-bounds (non-positive and greater than length) positions are allowed and can be used to get empty strings
	-- @returns a non-empty array of strings
	getTextBetween = function(self, begX, begY, edX, edY)
		local result = {}
		if edY < begY or edY == begY and edX < begX then
			table.insert(result, "")
			return result
		end
		for i = begY, edY do
			if i < 1 or i > #self._lines then
				table.insert(result, "")
			else
				local line = self._lines[i] or ""
				if i == edY then
					if edX < 1 then
						line = ""
					else
						line = sysencoding.sub(line, 1, edX)
					end
				end
				if i == begY then
					if begX >= 1 then
						line = sysencoding.sub(line, begX)
					end
				end
				table.insert(result, line)
			end
		end
		return result
	end,
	setTextBetween = function(self, txt, begX, begY, edX, edY)
		local oldTxt = self:getTextBetween(begX, begY, edX, edY)
		self:_setTextBetweenImpl(txt, begX, begY, edX, edY)
		txt = itertools.collect(ipairs(txt))

		local oldStateIndex = self._undoIndex
		local newStateIndex = self._undoList.n + 1
		local oldState = self._undoList[oldStateIndex]
		local childIndex = #oldState.children + 1
		local newState = {parent = oldStateIndex, parentChild = childIndex, x = begX, y = begY, children = {}}
		newState.added = itertools.collect(ipairs(txt))
		newState.removed = itertools.collect(ipairs(oldTxt))
		oldState.children[childIndex] = newStateIndex
		self._undoList[newStateIndex] = newState
		self._undoList.n = newStateIndex
		self._undoIndex = newStateIndex
	end,
	--- Deletes and pastes characterwise lines or their parts from an array
	-- Both beginning and ending characters are deleted
	-- If the ending is exactly one character before and in the same line as the beginning,
	-- nothing will be deleted
	-- If the ending is further before the beginning, nothing will be done
	-- @param txt a non-empty array of strings
	_setTextBetweenImpl = function(self, txt, begX, begY, edX, edY)
		if edY < begY or edY == begY and edX + 1 < begX then
			print(begX, begY, edX, edY)
			error()
			return
		end
		local oldTxt = {}
		local begLine = self._lines[begY] or ""
		local edLine = self._lines[edY] or ""
		local prefix, suffix
		if begX > 1 then
			prefix = sysencoding.sub(begLine, 1, begX - 1)
		else
			prefix = ""
		end
		if edX > 0 then
			suffix = sysencoding.sub(edLine, edX + 1)
		else
			suffix = edLine
		end
		for i = edY, begY, -1 do
			table.remove(self._lines, i)
			table.remove(self._cacheRoot, i)
		end
		for i, line in itertools.reversedIpairs(txt) do
			if i == #txt then
				line = line .. suffix
			end
			if i == 1 then
				line = prefix .. line
			end
			table.insert(self._lines, begY, line)
			table.insert(self._cacheRoot, begY, weakMap())
		end
	end,
	setFilename = function(self, name)
		self._filename = name
	end,
	getFilename = function(self)
		return self._filename
	end,
	undo = function(self)
		local state = self._undoList[self._undoIndex]
		local parentIndex = state.parent
		if not parentIndex then
			self:_echoInfo("Already at oldest change")
			return false
		end
		local parent = self._undoList[parentIndex]
		if not parent then
			self:_echoInfo("Already at oldest change (maximum undo depth reached)")
			return false
		end
		parent.redoIndex = state.parentChild
		local begX, begY = state.x, state.y
		local delLength = #state.added
		local edY = begY + delLength - 1
		local edX = sysencoding.len(state.added[delLength])
		if begY == edY then
			edX = begX + edX - 1
		end
		self:_setTextBetweenImpl(state.removed, begX, begY, edX, edY)
		self._undoIndex = parentIndex
		return true
	end,
	redo = function(self)
		local parent = self._undoList[self._undoIndex]
		local stateIndex = parent.children[parent.redoIndex or #parent.children]
		if not stateIndex then
			self:_echoInfo("Already at newest change")
			return false
		end
		local state = self._undoList[stateIndex]
		if not state then
			self:_echoInfo("Already at newest change (redo state deleted?)")
			return false
		end
		local begX, begY = state.x, state.y
		local delLength = #state.removed
		local edY = begY + delLength - 1
		local edX = sysencoding.len(state.removed[delLength])
		if begY == edY then
			edX = begX + edX - 1
		end
		self:_setTextBetweenImpl(state.added, begX, begY, edX, edY)
		self._undoIndex = stateIndex
		return true
	end,
}

local function fromFile(name)
	local buf = Buffer()
	buf:setFilename(name)
	buf:read()
	return buf
end

return {
	Buffer = Buffer,
	fromFile = fromFile,
}
