local textrender = require("vim.platform.textrender")
local safeencoding = require("vim.safeencoding")
local itertools = require("vim.itertools")
local makeClass = require("vim.makeclass")
local strptn = require("vim.strptn")
local helpers = require("vim.helpers")

local TABSTOP = 8

local function toPrintableStyled(line)
	local tabPositions = strptn.findAll(line, "\t")
	local invalidPositions = safeencoding.findAllInvalidCodePoints(line)
	local controlPositions = strptn.findAll(line, "[%z\x01-\x08\x0b-\x1f]", {pattern = true})
	local mergedPositions = strptn.matchesMerge({tab = tabPositions, inv = invalidPositions, ctl = controlPositions}, 1, "kind")
	local result = {}
	local adjustment = 0
	local start = 1
	local lineLen = safeencoding.len(line)
	for _, m in ipairs(mergedPositions) do
		if start < m[1] then
			table.insert(result, {
				string = safeencoding.sub(line, start, m[1] - 1),
				styleNames = {"normal"},
				firstCodePoint = start,
				lastCodePoint = m[1] - 1,
				firstColumn = start + adjustment,
				lastColumn = m[1] - 1 + adjustment,
			})
		end
		local startCol = m[1] + adjustment
		local width
		if m.kind == "tab" then
			width = TABSTOP - ((startCol - 1) % TABSTOP)
			rep = itertools.repeatString("-", width - 1) .. ">"
		else
			local value = safeencoding.sub(line, m[1], m[2]):byte()
			rep = ("<%02x>"):format(value)
			width = safeencoding.len(rep)
		end
		table.insert(result, {
			string = rep,
			styleNames = {"normal", "nontext"},
			firstCodePoint = m[1],
			lastCodePoint = m[2],
			firstColumn = m[1] + adjustment,
			lastColumn = m[1] + adjustment + width - 1,
		})
		adjustment = adjustment + width - 1
		start = m[2] + 1
	end
	if start <= lineLen then
		table.insert(result, {
			string = safeencoding.sub(line, start),
			styleNames = {"normal"},
			firstCodePoint = start,
			lastCodePoint = lineLen,
			firstColumn = start + adjustment,
			lastColumn = lineLen + adjustment,
		})
	end
	return result
end

local function printableStyledToView(orig, scrollX, contentWidth)
	local result = {}
	local firstCol = scrollX + 1
	local lastCol = scrollX + contentWidth
	for _, entry in ipairs(orig) do
		if entry.lastColumn >= firstCol and entry.firstColumn <= lastCol then
			if entry.lastColumn > lastCol then
				local s = safeencoding.sub(entry.string, 1, lastCol - entry.firstColumn + 1)
				entry = {
					string = s,
					styleNames = entry.styleNames,
					firstCodePoint = entry.firstCodePoint,
					lastCodePoint = entry.lastCodePoint,  -- Do not update
					firstColumn = entry.firstColumn,
					lastColumn = lastCol,
				}
			end
			if entry.firstColumn < firstCol then
				local amount = firstCol - entry.firstColumn
				local s = safeencoding.sub(entry.string, amount + 1)
				entry = {
					string = s,
					styleNames = entry.styleNames,
					firstCodePoint = entry.firstCodePoint + amount,
					lastCodePoint = entry.lastCodePoint,
					firstColumn = entry.firstColumn,
					lastColumn = entry.lastColumn,
				}
				if entry.lastCodePoint < entry.firstCodePoint then
					entry.firstCodePoint = entry.lastCodePoint
				end
			end
			table.insert(result, entry)
		end
	end
	local lastPresentCol = 0
	local lastPresentCodePoint = 0
	if #result > 0 then
		lastPresentCol = result[#result].lastColumn
		lastPresentCodePoint = result[#result].lastCodePoint
	end
	local rightPadLength = lastCol - lastPresentCol
	if rightPadLength > 0 then
		local rightPad = itertools.repeatString(" ", rightPadLength)
		local entry = {
			string = rightPad,
			styleNames = {"normal"},
			firstCodePoint = lastPresentCodePoint + 1,
			lastCodePoint = lastPresentCodePoint + rightPadLength,
			firstColumn = lastPresentCol,
			lastColumn = lastCol,
		}
		table.insert(result, entry)
	end
	return result
end

local function printableStyledAddHighlight(orig, lineBegX, lineEdX, styleNames)
	local result = {}
	for _, entry in ipairs(orig) do
		if lineEdX < entry.firstCodePoint or lineBegX > entry.lastCodePoint then
			table.insert(result, entry)
		else
			local entryLength = entry.lastCodePoint - entry.firstCodePoint + 1
			local begX = lineBegX - entry.firstCodePoint + 1
			local edX = lineEdX - entry.firstCodePoint + 1
			if begX < 1 then
				begX = 1
			end
			if edX > entryLength then
				edX = entryLength
			end
			local visualEdX = edX
			if entryLength == 1 then
				visualEdX = entry.lastColumn - entry.firstColumn + 1
			end
			if begX > 1 then
				local s = safeencoding.sub(entry.string, 1, begX - 1)
				local newEntry = {
					string = s,
					styleNames = entry.styleNames,
					firstCodePoint = entry.firstCodePoint,
					lastCodePoint = entry.firstCodePoint + begX - 2,
					firstColumn = entry.firstColumn,
					lastColumn = entry.firstColumn + begX - 2,
				}
				if newEntry.lastCodePoint > entry.lastCodePoint then
					newEntry.lastCodePoint = entry.lastCodePoint
				end
				table.insert(result, newEntry)
			end
			local s = safeencoding.sub(entry.string, begX, visualEdX)
			local styleWithVisual = itertools.collect(ipairs(entry.styleNames))
			for _, styleName in ipairs(styleNames) do
				styleWithVisual[#styleWithVisual + 1] = styleName
			end
			local newEntry = {
				string = s,
				styleNames = styleWithVisual,
				firstCodePoint = entry.firstCodePoint + begX - 1,
				lastCodePoint = entry.firstCodePoint + edX - 1,
				firstColumn = entry.firstColumn + begX - 1,
				lastColumn = entry.firstColumn + visualEdX - 1,
			}
			if newEntry.firstCodePoint > entry.lastCodePoint then
				newEntry.firstCodePoint = entry.lastCodePoint
			end
			if newEntry.lastCodePoint > entry.lastCodePoint then
				newEntry.lastCodePoint = entry.lastCodePoint
			end
			table.insert(result, newEntry)
			if visualEdX < safeencoding.len(entry.string) then
				local s = safeencoding.sub(entry.string, visualEdX + 1)
				local newEntry = {
					string = s,
					styleNames = entry.styleNames,
					firstCodePoint = entry.firstCodePoint + edX,
					lastCodePoint = entry.lastCodePoint,
					firstColumn = entry.firstColumn + visualEdX,
					lastColumn = entry.lastColumn,
				}
				if newEntry.firstCodePoint > entry.lastCodePoint then
					newEntry.firstCodePoint = entry.lastCodePoint
				end
				table.insert(result, newEntry)
			end
		end
	end
	return result
end

local function printableStyledAddVisual(orig, lineBegX, lineEdX)
	return printableStyledAddHighlight(orig, lineBegX, lineEdX, {"visual"})
end

local function printableStyledAddCursor(orig, cursorX, styleName)
	return printableStyledAddHighlight(orig, cursorX, cursorX, {styleName})
end

local function printableStyledAddHlsearch(orig, matches)
	for _, m in ipairs(matches) do
		local lineBegX, lineEdX = m[1], m[2]
		if lineEdX < lineBegX then
			lineEdX = lineBegX
		end
		orig = printableStyledAddHighlight(orig, lineBegX, lineEdX, {"search"})
	end
	return orig
end

local function printableStyledAddSyntaxRegions(orig, regions)
	-- TODO avoid quadratic complexity
	for _, region in ipairs(regions) do
		orig = printableStyledAddHighlight(orig, region.firstCodePoint, region.lastCodePoint, region.styleNames)
	end
	return orig
end

local function statusLineDataToPrintableStyled(data, contentWidth, focused)
	if not data then
		data = {cells = {""}, truncatePoint = {1, 0}}
	end
	local statusLineStyleName = "StatusLineNC"
	if focused then
		statusLineStyleName = "StatusLine"
	end
	local printableStyledCells = {}
	local cellLengthSum = 0
	local preTruncateLengthSum = 0
	for i, s in ipairs(data.cells) do
		local psc = toPrintableStyled(s)
		printableStyledCells[i] = psc
		local lastEntry = psc[#psc]
		if lastEntry then
			local cellLength = lastEntry.lastColumn
			cellLengthSum = cellLengthSum + cellLength
			if i < data.truncatePoint[1] then
				preTruncateLengthSum = preTruncateLengthSum + cellLength
			elseif i == data.truncatePoint[1] then
				local offset = data.truncatePoint[2]  -- TODO: find the column offset of the matching psc entry instead
				if offset > cellLength then
					offset = cellLength
				end
				preTruncateLengthSum = preTruncateLengthSum + offset
			end
		end
	end
	local postTruncateLengthSum = cellLengthSum - preTruncateLengthSum
	local remainingLength = contentWidth - cellLengthSum
	local dropLength = -remainingLength
	if remainingLength < 0 then
		local psc = printableStyledCells[data.truncatePoint[1]] or {}
		local colAdjustment = 0
		for i = 1, #psc do
			local entry = psc[i]
			if entry.lastCodePoint >= data.truncatePoint[2] then
				local offset = data.truncatePoint[2] - entry.firstCodePoint
				if offset < 0 then
					offset = 0
				end
				local entryWidth = entry.lastColumn - entry.firstColumn + 1
				entry.firstColumn = entry.firstColumn - colAdjustment
				entry.lastColumn = entry.lastColumn - colAdjustment
				if offset == 0 and dropLength >= entryWidth then
					colAdjustment = colAdjustment + entryWidth
					dropLength = dropLength - entryWidth
					remainingLength = remainingLength + entryWidth
					cellLengthSum = cellLengthSum - entryWidth
					entry.string = ""
					entry.lastColumn = entry.firstColumn - 1
				elseif dropLength > 0 then
					local amount = entryWidth - offset
					if amount > dropLength then
						amount = dropLength
					end
					colAdjustment = colAdjustment + amount
					entry.lastColumn = entry.lastColumn - amount
					dropLength = dropLength - amount
					remainingLength = remainingLength + amount
					cellLengthSum = cellLengthSum - amount
					entry.string = safeencoding.sub(entry.string, 1, offset) .. safeencoding.sub(entry.string, amount + offset + 1)
				end
			end
		end
		for cellIndex = data.truncatePoint[1] + 1, #printableStyledCells do
			if dropLength <= 0 then
				break
			end
			local psc = printableStyledCells[cellIndex]
			local lastEntry = psc[#psc]
			if lastEntry then
				local cellLength = lastEntry.lastColumn
				if dropLength >= cellLength then
					dropLength = dropLength - cellLength
					remainingLength = remainingLength + cellLength
					cellLengthSum = cellLengthSum - cellLength
					printableStyledCells[cellIndex] = {}
				else
					local colAdjustment = 0
					while psc[1] do
						if dropLength <= 0 then
							break
						end
						local entry = psc[1]
						local entryWidth = entry.lastColumn - entry.firstColumn + 1
						if dropLength >= entryWidth then
							colAdjustment = colAdjustment + entryWidth
							dropLength = dropLength - entryWidth
							remainingLength = remainingLength + entryWidth
							cellLengthSum = cellLengthSum - entryWidth
							table.remove(psc, 1)
						else
							colAdjustment = colAdjustment + dropLength
							entry.firstColumn = entry.firstColumn + dropLength
							dropLength = dropLength - entryWidth
							remainingLength = remainingLength + entryWidth
							cellLengthSum = cellLengthSum - entryWidth
							entry.string = safeencoding.sub(entry.string, dropLength + 1)
						end
					end
					for _, entry in ipairs(psc) do
						entry.firstColumn = entry.firstColumn - colAdjustment
						entry.lastColumn = entry.lastColumn - colAdjustment
					end
				end
			end
		end
		for cellIndex = data.truncatePoint[1], 1, -1 do
			if dropLength <= 0 then
				break
			end
			local psc = printableStyledCells[cellIndex]
			for i = #psc, 1, -1 do
				if dropLength <= 0 then
					break
				end
				local entry = psc[i]
				local entryWidth = entry.lastColumn - entry.firstColumn + 1
				if dropLength >= entryWidth then
					dropLength = dropLength - entryWidth
					remainingLength = remainingLength + entryWidth
					cellLengthSum = cellLengthSum - entryWidth
					psc[i] = nil
				else
					entry.string = safeencoding.sub(entry.string, 1, entryWidth - dropLength)
					entry.lastColumn = entry.lastColumn - dropLength
				end
			end
		end
	else
		dropLength = 0
	end
	local separatorLength = 0
	local separator = ""
	local numSeparators = #data.cells - 1
	if numSeparators > 0 then
		separatorLength = math.floor(remainingLength / numSeparators)
		separator = itertools.repeatString(" ", separatorLength)
	end
	local rightPadLength = remainingLength - numSeparators * separatorLength
	local result = {}
	local lastPresentCodePoint = 0
	local lastPresentCol = 0
	for cellIndex, psc in ipairs(printableStyledCells) do
		if cellIndex > 1 and separatorLength > 0 then
			local entry = {
				string = separator,
				styleNames = {"normal", statusLineStyleName},
				firstCodePoint = lastPresentCodePoint + 1,
				lastCodePoint = lastPresentCodePoint + separatorLength,
				firstColumn = lastPresentCol + 1,
				lastColumn = lastPresentCol + separatorLength,
			}
			table.insert(result, entry)
			lastPresentCodePoint = lastPresentCodePoint + separatorLength
			lastPresentCol = lastPresentCol + separatorLength
		end
		local codePointAdjustment = lastPresentCodePoint
		local colAdjustment = lastPresentCol
		for _, entry in ipairs(psc) do
			local newStyle = itertools.collect(ipairs(entry.styleNames))
			table.insert(newStyle, 2, statusLineStyleName)
			entry.styleNames = newStyle
			entry.firstCodePoint = entry.firstCodePoint + codePointAdjustment
			entry.lastCodePoint = entry.lastCodePoint + codePointAdjustment
			entry.firstColumn = entry.firstCodePoint + colAdjustment
			entry.lastColumn = entry.lastCodePoint + colAdjustment
			lastPresentCodePoint = entry.lastCodePoint
			lastPresentCol = entry.lastColumn
			table.insert(result, entry)
		end
	end
	if rightPadLength > 0 then
		rightPad = itertools.repeatString(" ", rightPadLength)
		local entry = {
			string = rightPad,
			styleNames = {"normal", statusLineStyleName},
			firstCodePoint = lastPresentCodePoint + 1,
			lastCodePoint = lastPresentCodePoint + rightPadLength,
			firstColumn = lastPresentCol + 1,
			lastColumn = contentWidth,
		}
		table.insert(result, entry)
	end
	return result
end

local Window = makeClass {
	init = function(self, buffer)
		self.currentBuffer = buffer
		self._scrollX = 0
		self._scrollY = 0
		self._focused = false
		self._skipNonce = {}
		self._renderedCursorX = nil
		self._renderedCursorY = nil
		self._bufferCursors = setmetatable({}, {__mode = "k"})
	end,
	setEditor = function(self, editor)
		self._editor = editor
	end,
	getBufferCursor = function(self, buf)
		if not buf then
			return nil
		end
		local pos = self._bufferCursors[buf]
		if not pos then
			pos = buf:trackPosition()
			self._bufferCursors[buf] = pos
		end
		return pos
	end,
	getCurrentCursor = function(self)
		return self:getBufferCursor(self.currentBuffer)
	end,
	getCursorXY = function(self)
		local pos = self:getCurrentCursor()
		if not pos then
			return 1, 1
		end
		return pos.x, pos.y
	end,
	invalidateDisplay = function(self)
		self._skipNonce = {}
	end,
	render = function(self)
		local eobStyle = self._editor:interpretStyleStack{"normal", "endofbuffer"}
		local lineNrStyle = self._editor:interpretStyleStack{"normal", "linenr"}
		local statusLineStyle = self._editor:interpretStyleStack{"normal", "statusline"}
		local eobChunk = {"~"}
		itertools.update(eobChunk, eobStyle)
		local width, height = textrender.getTermSize()
		height = height - 1  -- MsgArea is not managed by the window
		eobChunk[1] = eobChunk[1] .. itertools.repeatString(" ", width - 1)
		local n = self.currentBuffer:getLineCount()
		local maxNrDigits = safeencoding.len(tostring(n))
		local contentWidth = width - maxNrDigits - 1
		local contentHeight = height - 1  -- Reserve status line space
		local cursorX, cursorY = self:getCursorXY()
		local cursorViewportX, cursorViewportY = self:projectToContent(cursorX, cursorY)
		local visualBoundaries = nil
		if self._visualSelection then
			visualBoundaries = {helpers.getTextObjectEnds(self._editor, helpers.finalizeMotion(self._editor, self._visualSelection))}
		end
		local searchString = nil
		if self._editor.hlsearch then
			searchString = helpers.getSearchString(self._editor)
		end
		for i = 1, height do
			local lineNr = i + self._scrollY
			local canSkip = true
			local skipInfo = self.currentBuffer:getScopedLineCache(lineNr, self._skipNonce)
			canSkip = canSkip and skipInfo and skipInfo.lineNr == lineNr
			if self._renderedCursorY == cursorY then
				if cursorY == lineNr then
					canSkip = canSkip and self._renderedCursorX == cursorX
				end
			else
				canSkip = canSkip and lineNr ~= cursorY
				canSkip = canSkip and lineNr ~= self._renderedCursorY
			end
			self._renderedCursorX = nil
			self._renderedCursorY = nil
			if not canSkip then
				textrender.setCursorPos(1, i)
				if lineNr <= n then
					local nrString = tostring(lineNr)
					while safeencoding.len(nrString) < maxNrDigits do
						nrString = " " .. nrString
					end
					local nrChunk = {nrString .. " "}
					itertools.update(nrChunk, lineNrStyle)
					local blitData = {nrChunk}

					local psl = self:_getPrintableStyledLine(lineNr)
					if self._editor.enableSyntax then
						local regions = self.currentBuffer.syntaxRegistry:getRegions(self.currentBuffer, lineNr)
						psl = printableStyledAddSyntaxRegions(psl, regions)
					end
					if searchString then
						local matches = helpers.getLineSearchMatches(self._editor, searchString, lineNr)
						if matches then
							psl = printableStyledAddHlsearch(psl, matches)
						end
					end
					if visualBoundaries and lineNr >= visualBoundaries[2] and lineNr <= visualBoundaries[4] then
						local begX, edX = 1, 1
						if #psl > 0 then
							edX = psl[#psl].lastCodePoint
						end
						if lineNr == visualBoundaries[2] then
							begX = visualBoundaries[1]
						end
						if lineNr == visualBoundaries[4] then
							edX = visualBoundaries[3]
						end
						psl = printableStyledAddVisual(psl, begX, edX)
					end
					psl = printableStyledToView(psl, self._scrollX, contentWidth)
					if cursorViewportY == i and cursorViewportX > 0 then
						local cursorStyleName = "cursornc"
						if self._focused then
							cursorStyleName = "cursor"
						end
						psl = printableStyledAddCursor(psl, cursorX, cursorStyleName)  -- Cursor is bound to codepoints rather than columns, and codepoints are not affected by scrolling
						self._renderedCursorX = cursorX
						self._renderedCursorY = cursorY
					end
					for _, entry in ipairs(psl) do
						local chunk = {entry.string}
						local style = self._editor:interpretStyleStack(entry.styleNames)
						itertools.update(chunk, style)
						table.insert(blitData, chunk)
					end

					textrender.blitAll(blitData)
					self.currentBuffer:setScopedLineCache(lineNr, self._skipNonce, {lineNr = lineNr})
				else
					textrender.blitAll{
						eobChunk,
					}
				end
			end
		end

		-- Status line
		textrender.setCursorPos(1, height)
		local blitData = {}
		for _, entry in ipairs(statusLineDataToPrintableStyled(helpers.populateStatusLineData(self._editor, self, helpers.getEffectiveStatusLineFormatString(self._editor)), width, self._focused)) do
			local chunk = {entry.string}
			local style = self._editor:interpretStyleStack(entry.styleNames)
			itertools.update(chunk, style)
			table.insert(blitData, chunk)
		end
		textrender.blitAll(blitData)
	end,
	getContentSize = function(self)
		local width, height = textrender.getTermSize()
		height = height - 1  -- MsgArea is not managed by the window
		local maxNrDigits = 0
		if self.currentBuffer then
			local n = self.currentBuffer:getLineCount()
			maxNrDigits = safeencoding.len(tostring(n))
		end
		local contentWidth = width - maxNrDigits - 1
		local contentHeight = height - 1  -- Reserve status line space
		return contentWidth, contentHeight
	end,
	getScrollAmount = function(self)
		return self._scrollX, self._scrollY
	end,
	setScrollAmount = function(self, x, y)
		self._scrollX = x
		self._scrollY = y
		self:invalidateDisplay()
	end,
	_getPrintableStyledLine = function(self, y)
		local result = self.currentBuffer:getScopedLineCache(y, "printableStyled")
		if result == nil then
			local line = self.currentBuffer:getLine(y)
			if line == nil then
				return nil
			end
			result = toPrintableStyled(line)
			self.currentBuffer:setScopedLineCache(y, "printableStyled", result)
		end
		return result
	end,
	setVisualSelection = function(self, toCtx)
		if self._visualSelection then
			local begY, edY = self._visualSelection.initialY, self._visualSelection.y
			if begY > edY then
				begY, edY = edY, begY
			end
			for i = begY, edY do
				self.currentBuffer:setScopedLineCache(i, self._skipNonce, nil)
			end
		end
		if toCtx then
			local begY, edY = toCtx.initialY, toCtx.y
			if begY > edY then
				begY, edY = edY, begY
			end
			for i = begY, edY do
				self.currentBuffer:setScopedLineCache(i, self._skipNonce, nil)
			end
		end
		self._visualSelection = toCtx
	end,
	setFocused = function(self, flag)
		self._focused = flag
		self:invalidateDisplay()
	end,
	isFocused = function(self)
		return self._focused
	end,
	--- Convert window content position to buffer position
	unprojectFromContent = function(self, contentX, contentY)
		local contentWidth, contentHeight = self:getContentSize()
		local scrollX, scrollY = self:getScrollAmount()
		local bufY = contentY + scrollY
		local psl = self:_getPrintableStyledLine(bufY)
		local unscrolledContentX = scrollX + contentX
		if not psl or #psl < 1 then
			return unscrolledContentX, bufY
		end
		for i, entry in ipairs(psl) do
			if entry.firstColumn > unscrolledContentX then
				return entry.firstCodePoint - entry.firstColumn + contentX + scrollX, bufY
			end
			if entry.lastColumn >= unscrolledContentX then
				local bufX = entry.firstCodePoint - entry.firstColumn + contentX
				if bufX > entry.lastCodePoint then
					bufX = entry.lastCodePoint
				end
				bufX = bufX + scrollX
				return bufX, bufY
			end
		end
		local lastEntry = psl[#psl]
		return contentX - lastEntry.lastColumn + lastEntry.lastCodePoint + scrollX, bufY
	end,
	--- Convert screen position to buffer position
	unproject = function(self, screenX, screenY)
		local lineNrWidth = safeencoding.len(tostring(self.currentBuffer:getLineCount())) + 1
		return self:unprojectFromContent(screenX - lineNrWidth, screenY)
	end,
	--- Convert buffer position to (potential) window content position
	projectToContent = function(self, bufX, bufY)
		local scrollX, scrollY = self:getScrollAmount()
		local psl = self:_getPrintableStyledLine(bufY)
		local contentY = bufY - scrollY
		if not psl or #psl < 1 then
			return bufX - scrollX, contentY
		end
		for i, entry in ipairs(psl) do
			if entry.firstCodePoint > bufX then
				return entry.firstColumn - scrollX - entry.firstCodePoint + bufX, contentY
			end
			if entry.lastCodePoint >= bufX then
				local contentX = entry.firstColumn - entry.firstCodePoint + bufX
				if contentX > entry.lastColumn then
					contentX = entry.lastColumn
				end
				contentX = contentX - scrollX
				return contentX, contentY
			end
		end
		local lastEntry = psl[#psl]
		return bufX - lastEntry.lastCodePoint + lastEntry.lastColumn - scrollX, contentY
	end,
	--- Convert buffer position to (potential) screen position
	project = function(self, bufX, bufY)
		local lineNrWidth = safeencoding.len(tostring(self.currentBuffer:getLineCount())) + 1
		local contentX, contentY = self:projectToContent(bufX, bufY)
		return contentX + lineNrWidth, contentY
	end,
}

local function withBuffer(buf)
	return Window(buf)
end

return {
	withBuffer = withBuffer,

	-- TODO extract to a separate file
	toPrintableStyled = toPrintableStyled,
	printableStyledToView = printableStyledToView,
	printableStyledAddCursor = printableStyledAddCursor,
}
