local textrender = require("vim.platform.textrender")
local sysencoding = require("vim.platform.sysencoding")
local itertools = require("vim.itertools")
local makeClass = require("vim.makeclass")
local strptn = require("vim.strptn")
local helpers = require("vim.helpers")

local TABSTOP = 8

local function toPrintableStyled(line)
	-- TODO non-printable
	local tabPositions = strptn.findAll(line, "\t")
	local result = {}
	local adjustment = 0
	local start = 1
	local lineLen = sysencoding.len(line)
	for _, m in ipairs(tabPositions) do
		if start < m[1] then
			table.insert(result, {
				string = sysencoding.sub(line, start, m[1] - 1),
				styleNames = {"normal"},
				firstCodePoint = start,
				lastCodePoint = m[1] - 1,
				firstColumn = start + adjustment,
				lastColumn = m[1] - 1 + adjustment,
			})
		end
		local startCol = m[1] + adjustment
		local width = TABSTOP - ((startCol - 1) % TABSTOP)
		table.insert(result, {
			string = itertools.repeatString("-", width - 1) .. ">",
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
			string = sysencoding.sub(line, start),
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
				local s = sysencoding.sub(entry.string, 1, lastCol - entry.firstColumn + 1)
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
				local s = sysencoding.sub(entry.string, amount + 1)
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

local function printableStyledAddHighlight(orig, lineBegX, lineEdX, styleName)
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
			if begX > 1 then
				local s = sysencoding.sub(entry.string, 1, begX - 1)
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
			local s = sysencoding.sub(entry.string, begX, edX)
			local styleWithVisual = itertools.collect(ipairs(entry.styleNames))
			styleWithVisual[#styleWithVisual + 1] = styleName
			local newEntry = {
				string = s,
				styleNames = styleWithVisual,
				firstCodePoint = entry.firstCodePoint + begX - 1,
				lastCodePoint = entry.firstCodePoint + edX - 1,
				firstColumn = entry.firstColumn + begX - 1,
				lastColumn = entry.firstColumn + edX - 1,
			}
			if newEntry.firstCodePoint > entry.lastCodePoint then
				newEntry.firstCodePoint = entry.lastCodePoint
			end
			if newEntry.lastCodePoint > entry.lastCodePoint then
				newEntry.lastCodePoint = entry.lastCodePoint
			end
			table.insert(result, newEntry)
			if edX < sysencoding.len(entry.string) then
				local s = sysencoding.sub(entry.string, edX + 1)
				local newEntry = {
					string = s,
					styleNames = entry.styleNames,
					firstCodePoint = entry.firstCodePoint + edX,
					lastCodePoint = entry.lastCodePoint,
					firstColumn = entry.firstColumn + edX,
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
	return printableStyledAddHighlight(orig, lineBegX, lineEdX, "visual")
end

local function printableStyledAddCursor(orig, cursorX, styleName)
	return printableStyledAddHighlight(orig, cursorX, cursorX, styleName)
end

local function printableStyledAddHlsearch(orig, matches)
	for _, m in ipairs(matches) do
		orig = printableStyledAddHighlight(orig, m[1], m[2], "search")
	end
	return orig
end

local Window = makeClass {
	init = function(self, buffer)
		self.currentBuffer = buffer
		self._scrollX = 0
		self._scrollY = 0
		self._focused = false
	end,
	setEditor = function(self, editor)
		self._editor = editor
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
		local maxNrDigits = sysencoding.len(tostring(n))
		local contentWidth = width - maxNrDigits - 1
		local contentHeight = height - 1  -- Reserve status line space
		local cursorX = self._editor._cursorX or 1
		local cursorY = self._editor._cursorY or 1
		local cursorViewportX = cursorX - self._scrollX
		local cursorViewportY = cursorY - self._scrollY
		local visualBoundaries = nil
		if self._visualSelection then
			visualBoundaries = {helpers.getTextObjectEnds(self._editor, helpers.finalizeMotion(self._editor, self._visualSelection))}
		end
		local searchString = nil
		if self._editor.hlsearch then
			searchString = helpers.getSearchString(self._editor)
		end
		for i = 1, height do
			textrender.setCursorPos(1, i)
			local lineNr = i + self._scrollY
			if lineNr <= n then
				local nrString = tostring(lineNr)
				while sysencoding.len(nrString) < maxNrDigits do
					nrString = " " .. nrString
				end
				local nrChunk = {nrString .. " "}
				itertools.update(nrChunk, lineNrStyle)
				local blitData = {nrChunk}

				local psl = self:_getPrintableStyledLine(lineNr)
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
				end
				for _, entry in ipairs(psl) do
					local chunk = {entry.string}
					local style = self._editor:interpretStyleStack(entry.styleNames)
					itertools.update(chunk, style)
					table.insert(blitData, chunk)
				end

				textrender.blitAll(blitData)
			else
				textrender.blitAll{
					eobChunk,
				}
			end
		end

		-- Status line
		textrender.setCursorPos(1, height)
		local filename = self.currentBuffer:getFilename()
		filename = sysencoding.sub(filename, 1, width)
		local remainingLength = width - sysencoding.len(filename)
		local rightPad = ""
		if remainingLength > 0 then
			rightPad = itertools.repeatString(" ", remainingLength)
		end
		local filenameChunk = {filename .. rightPad}
		itertools.update(filenameChunk, statusLineStyle)
		textrender.blitAll{
			filenameChunk,
		}
	end,
	getContentSize = function(self)
		local width, height = textrender.getTermSize()
		height = height - 1  -- MsgArea is not managed by the window
		local maxNrDigits = 0
		if self.currentBuffer then
			local n = self.currentBuffer:getLineCount()
			maxNrDigits = sysencoding.len(tostring(n))
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
		self._visualSelection = toCtx
	end,
	setFocused = function(self, flag)
		self._focused = flag
	end,
	isFocused = function(self)
		return self._focused
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
