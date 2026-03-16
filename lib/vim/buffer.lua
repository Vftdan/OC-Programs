local makeClass = require("vim.makeclass")
local safeencoding = require("vim.safeencoding")
local itertools = require("vim.itertools")
local syntax = require("vim.syntax")

local weakMapMeta = {__mode = "k"}
local function weakMap()
	return setmetatable({}, weakMapMeta)
end

local TrackedPosition = makeClass {
	init = function(self)
		self.x = 1
		self.y = 1
		self.wantX = nil
	end,
	compareTo = function(self, other)
		if self.y < other.y then
			return -1
		elseif self.y > other.y then
			return 1
		elseif self.x < other.x then
			return -1
		elseif self.x > other.x then
			return 1
		end
		return 0
	end,
}

-- FIXME interference with scoped cache
-- Having overlapping staging changes is illegal
local StagingChange = makeClass {
	init = function(self, buf, begX, begY, edX, edY)
		if edY < begY or edY == begY and edX + 1 < begX then
			print(begX, begY, edX, edY)
			error()
			return
		end
		self._finalized = false
		self._visible = true
		self._buf = buf
		self._startPos = buf:trackPosition()
		self._startPos.x = begX
		self._startPos.y = begY
		self._savedStartPos = {x = begX, y = begY}
		self._delDY = edY - begY
		if self._delDY == 0 then
			self._delDX = edX - begX
		else
			self._delEdX = edX
		end
		self._txt = {""}
	end,
	_assertNotFinalized = function(self)
		if self._finalized then
			error("Modifying finalized StagingChange")
		end
	end,
	isFinalized = function(self)
		return self._finalized
	end,
	_saveStartPos = function(self)
		self._savedStartPos.x = self._startPos.x
		self._savedStartPos.y = self._startPos.y
	end,
	_restoreStartPos = function(self)
		self._startPos.x = self._savedStartPos.x
		self._startPos.y = self._savedStartPos.y
	end,
	setVisible = function(self, newVal)
		self:_assertNotFinalized()
		newVal = not not newVal
		if self._visible == newVal then
			return
		end
		self._visible = newVal
		local begX, begY, edX, edY, newEdX, newEdY = self:getBounds()
		if not newVal then
			edX, newEdX = newEdX, edX
			edY, newEdY = newEdY, edY
		end
		self:_saveStartPos()
		self._buf:adjustPositionsAndCache(begX, begY, edX, edY, newEdX, newEdY)
		self:_restoreStartPos()
	end,
	isVisible = function(self)
		return self._visible
	end,
	getBounds = function(self)
		local begX = self._startPos.x
		local begY = self._startPos.y
		local edY = begY + self._delDY
		local edX
		if begY == edY then
			edX = begX + self._delDX
		else
			edX = self._delEdX
		end
		local txt = self._txt
		local newEdY = begY + #txt - 1
		local newEdX
		if #txt < 2 then
			-- May be wrong with some encoding shenanigans
			newEdX = begX - 1 + safeencoding.len(txt[1])
		else
			newEdX = safeencoding.len(txt[#txt])
		end
		return begX, begY, edX, edY, newEdX, newEdY
	end,
	commit = function(self)
		self:_assertNotFinalized()
		local begX, begY, edX, edY, newEdX, newEdY = self:getBounds()
		self:setVisible(false)
		self._finalized = true
		self._buf:setTextBetween(self._txt, begX, begY, edX, edY)
	end,
	discard = function(self)
		self:_assertNotFinalized()
		self:setVisible(false)
		self._finalized = true
	end,
	splice = function(self, newTxt, relBegX, relBegY, relEdX, relEdY)
		self:_assertNotFinalized()
		if relEdY < relBegY or relEdY == relBegY and relEdX + 1 < relBegX then
			error("Wrong staging change splice ends order")
			return
		end
		local ownBegX, ownBegY = self._startPos.x, self._startPos.y
		local ownTxt = self._txt
		local begLine = ownTxt[relBegY]
		local edLine = ownTxt[relEdY]
		local prefix, suffix
		if relBegX > 1 then
			prefix = safeencoding.sub(begLine, 1, relBegX - 1)
		else
			prefix = ""
		end
		if relEdX > 0 then
			suffix = safeencoding.sub(edLine, relEdX + 1)
		else
			suffix = edLine
		end
		for i = relEdY, relBegY, -1 do
			table.remove(ownTxt, i)
		end
		for i, line in itertools.reversedIpairs(newTxt) do
			if i == #newTxt then
				line = line .. suffix
			end
			if i == 1 then
				line = prefix .. line
			end
			table.insert(ownTxt, relBegY, line)
		end
		if self._visible then
			local begY = ownBegY + relBegY - 1
			local begX
			if relBegY == 1 then
				begX = ownBegX + relBegX - 1
			else
				begX = relBegX
			end
			local edY = ownBegY + relEdY - 1
			local edX
			if relEdY == 1 then
				edX = ownBegX + relEdX - 1
			else
				edX = relEdX
			end
			local newEdY = begY + #newTxt - 1
			local newEdX
			if #newTxt < 2 then
				newEdX = begX - 1 + safeencoding.len(newTxt[1])
			else
				newEdX = safeencoding.len(newTxt[#newTxt])
			end
			self:_saveStartPos()
			self._buf:adjustPositionsAndCache(begX, begY, edX, edY, newEdX, newEdY)
			self:_restoreStartPos()
		end
	end,
	getBuffer = function(self)
		return self._buf
	end,
	getText = function(self)
		return itertools.collect(ipairs(self._txt))
	end,
}

local Buffer = makeClass {
	init = function(self)
		self._lines = {""}
		self._cacheRoot = {}
		self._undoList = {{children = {}}, n = 1}
		self._undoIndex = 1
		self._trackedPositions = weakMap()
		self._stagingChanges = {}
		self.syntaxRegistry = syntax.Syntax()
		self.syntaxName = ""
		self.lastChangeStart = self:trackPosition()
		self.lastChangeEnd = self:trackPosition()
		-- Selection bounds are not sorted
		self.lastFinishedSelectionStart = self:trackPosition()
		self.lastFinishedSelectionEnd = self:trackPosition()
		self.lastFinishedSelectionMeta = nil
		self.insertStagingStack = {}
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
	getLineCountNonStaging = function(self)
		return #self._lines
	end,
	getLineCount = function(self)
		local numLines = self:getLineCountNonStaging()
		for _, change in ipairs(self._stagingChanges) do
			if change:isVisible() then
				local _, _, _, edY, _, newEdY = change:getBounds()
				numLines = numLines + (newEdY - edY)
			end
		end
		return numLines
	end,
	getLineNonStaging = function(self, i)
		return self._lines[i]
	end,
	getLine = function(self, i)
		local changeIndex = 1
		local change = self._stagingChanges[changeIndex]
		local line = nil
		local di = 0
		while change do
			local _, begY, edX, edY, _, newEdY = change:getBounds()
			if begY >= i then
				break
			end
			if change:isVisible() then
				local txt = change._txt
				if i < newEdY then
					return txt[i - begY + 1]
				elseif i == newEdY then
					line = self:getLineNonStaging(edY + di) or ""
					if begY == edY then
						line = safeencoding.sub(line, edX + 1)
					end
					line = txt[#txt] .. line
				end
				di = di - (newEdY - edY)
			end
			changeIndex = changeIndex + 1
			change = self._stagingChanges[changeIndex]
		end
		if line == nil then
			line = self:getLineNonStaging(i + di) or ""
		end
		while change do
			if change:isVisible() then
				local begX, begY, edX, edY, newEdX, newEdY = change:getBounds()
				local txt = change._txt
				local suffix
				if begY == edY then
					suffix = safeencoding.sub(line, edX + 1)
				else
					local followingLine = self:getLineNonStaging(edY + di) or ""
					suffix = safeencoding.sub(followingLine, edX + 1)
				end
				di = di - (newEdY - edY)
				line = safeencoding.sub(line, 1, begX - 1)
				line = line .. txt[1]
				if newEdY > begY then
					return line
				end
				line = line .. suffix
			end
			changeIndex = changeIndex + 1
			change = self._stagingChanges[changeIndex]
		end
		return line
	end,
	_insertLine = function(self, i, line)
		local changeIndex = 1
		while self._stagingChanges[changeIndex] do
			local change = self._stagingChanges[changeIndex]
			local _, begY, _, edY, _, newEdY = change:getBounds()
			if begY >= i then
				break
			end
			if change:isVisible() then
				i = i + (newEdY - edY)
			end
		end
		table.insert(self._lines, i, line)
	end,
	_removeLine = function(self, i)
		local changeIndex = 1
		while self._stagingChanges[changeIndex] do
			local change = self._stagingChanges[changeIndex]
			local _, begY, _, edY, _, newEdY = change:getBounds()
			if begY >= i then
				break
			end
			if change:isVisible() then
				i = i + (newEdY - edY)
			end
		end
		return table.remove(self._lines, i)
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
		local found = false
		if f ~= nil then
			found = true
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
		self:discardStagingChanges()
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
		return found
	end,
	write = function(self, opts)
		opts = opts or {}
		-- TODO writebackup
		filename = opts.filename or self._filename
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
		if opts.lastLine and opts.lastLine < numLines then
			numLines = opts.lastLine
		end
		local bufOffset = (opts.firstLine or 1) - 1
		if bufOffset < 0 then
			bufOffset = 0
		end
		numLines = numLines - bufOffset
		local writtenLines = 0
		if numLines > 0 then
			success, reason = pcall(f.write, f, self:getLine(1 + bufOffset))
			if success then
				writtenLines = 1
			end
		else
			success, reason = pcall(f.write, f, "")
		end
		for i = 2, numLines do
			if success then
				success, reason = pcall(f.write, f, "\n" .. self:getLine(i + bufOffset))
				if success then
					writtenLines = writtenLines + 1
				end
			else
				break
			end
		end
		local writtenInfo = string.format("%q %dL written", filename, numLines)
		if not success then
			self:_echoError("Error while writing:", reason, "; Potentially", writtenInfo)
			return
		end
		success, reason = pcall(f.close, f)
		if not success then
			self:_echoError("Error while closing:", reason, "; Potentially", writtenInfo)
			return
		end
		self:_echoInfo(writtenInfo)
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
		local numLines = self:getLineCount()
		for i = begY, edY do
			if i < 1 or i > numLines then
				table.insert(result, "")
			else
				local line = self:getLine(i) or ""
				if i == edY then
					if edX < 1 then
						line = ""
					else
						line = safeencoding.sub(line, 1, edX)
					end
				end
				if i == begY then
					if begX >= 1 then
						line = safeencoding.sub(line, begX)
					end
				end
				table.insert(result, line)
			end
		end
		return result
	end,
	setTextBetween = function(self, txt, begX, begY, edX, edY)
		self:commitStagingChanges()
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
		local begLine = self:getLine(begY) or ""
		local edLine = self:getLine(edY) or ""
		local prefix, suffix
		if begX > 1 then
			prefix = safeencoding.sub(begLine, 1, begX - 1)
		else
			prefix = ""
		end
		if edX > 0 then
			suffix = safeencoding.sub(edLine, edX + 1)
		else
			suffix = edLine
		end
		for i = edY, begY, -1 do
			self:_removeLine(i)
		end
		for i, line in itertools.reversedIpairs(txt) do
			if i == #txt then
				line = line .. suffix
			end
			if i == 1 then
				line = prefix .. line
			end
			self:_insertLine(begY, line)
		end
		local newEdY = begY + #txt - 1
		local newEdX
		if #txt < 2 then
			newEdX = safeencoding.len(prefix .. txt[1])
		else
			newEdX = safeencoding.len(txt[#txt])
		end
		self:adjustPositionsAndCache(begX, begY, edX, edY, newEdX, newEdY)
		self.lastChangeStart.y = begY
		self.lastChangeStart.x = begX
		self.lastChangeEnd.y = newEdY
		self.lastChangeEnd.x = newEdX
	end,
	adjustPositionsAndCache = function(self, begX, begY, edX, edY, newEdX, newEdY)
		for i = edY, begY, -1 do
			table.remove(self._cacheRoot, i)
		end
		for i = begY, newEdY do
			table.insert(self._cacheRoot, i, weakMap())
		end
		for pos in pairs(self._trackedPositions) do
			if pos.y > begY or pos.y == begY and pos.x >= begX then
				if pos.y > edY then
					pos.y = pos.y - edY + newEdY
				elseif pos.y == edY then
					pos.y = newEdY
					if pos.x >= edX then
						pos.x = pos.x - edX + newEdX
					elseif pos.x > newEdX then
						pos.x = newEdX
					end
				else
					if pos.y > newEdY then
						pos.y = newEdY
					end
					local line = self:getLine(pos.y)
					local maxX = safeencoding.len(line)
					if maxX < 1 then
						maxX = 1
					end
					if pos.x > maxX then
						pos.x = maxX
					end
				end
			end
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
		local edX = safeencoding.len(state.added[delLength])
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
		local edX = safeencoding.len(state.removed[delLength])
		if begY == edY then
			edX = begX + edX - 1
		end
		self:_setTextBetweenImpl(state.added, begX, begY, edX, edY)
		self._undoIndex = stateIndex
		return true
	end,
	trackPosition = function(self)
		local pos = TrackedPosition()
		self._trackedPositions[pos] = true
		return pos
	end,
	startStagingChange = function(self, begX, begY, edX, edY)
		local change = StagingChange(self, begX, begY, edX, edY)
		local startPos = change._startPos
		local i = 1
		-- Consider binary search if a big number of changes is expected
		while self._stagingChanges[i] do
			local other = self._stagingChanges[i]
			local cmp = startPos:compareTo(other._startPos)
			if cmp >= 0 then
				break
			end
			i = i + 1
		end
		table.insert(self._stagingChanges, i, change)
		return change
	end,
	cleanFinalizedChanges = function(self)
		local i = #self._stagingChanges
		while i > 0 do
			if self._stagingChanges[i]._finalized then
				table.remove(self._stagingChanges, i)
			end
			i = i - 1
		end
	end,
	commitStagingChanges = function(self)
		for _, change in ipairs(self._stagingChanges) do
			if not change:isFinalized() then
				change:commit()
			end
		end
		self._stagingChanges = {}
	end,
	discardStagingChanges = function(self)
		for _, change in ipairs(self._stagingChanges) do
			if not change:isFinalized() then
				change:discard()
			end
		end
		self._stagingChanges = {}
	end,
	findStagingChangeByPos = function(self, pos, opts)
		opts = opts or {}
		local i = 1
		-- Consider binary search if a big number of changes is expected
		while self._stagingChanges[i] do
			local change = self._stagingChanges[i]
			local begX, begY, _, _, newEdX, newEdY = change:getBounds()
			if opts.exclusive then
				begX = begX - 1
			end
			local cmp = TrackedPosition.compareTo(pos, {x = begX, y = begY})
			if cmp >= 0 then
				if opts.onePastEnd then
					newEdX = newEdX + 1
				end
				if TrackedPosition.compareTo(pos, {x = newEdX, y = newEdY}) <= 0 then
					local relY = pos.y - begY + 1
					local relX
					if relY == 1 then
						relX = pos.x - begX
						if not opts.exclusive then
							relX = relX + 1
						end
					else
						relX = pos.x
					end
					return change, relX, relY
				end
			end
			i = i + 1
		end
		return nil, nil, nil
	end,
}

local function fromFile(name)
	local buf = Buffer()
	buf:setFilename(name)
	local found = buf:read()
	return buf, found
end

return {
	Buffer = Buffer,
	fromFile = fromFile,
}
