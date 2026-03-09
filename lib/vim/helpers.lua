local safeencoding = require("vim.safeencoding")
local itertools = require("vim.itertools")
local textrender = require("vim.platform.textrender")
local strptn = require("vim.strptn")
local typeahead = require("vim.typeahead")
local command
local modes

local function appendTextAtBuffer(editor, buf, tbl, x, y)
	if buf == nil then
		return
	end
	local oldLine = buf:getLine(y)
	local oldLineLen = safeencoding.len(oldLine)
	if x < 0 then
		x = 0
	elseif x > oldLineLen then
		x = oldLineLen
	end
	buf:setTextBetween(tbl, x + 1, y, x, y)
end

local function appendTextAt(editor, tbl, x, y)
	appendTextAtBuffer(editor, editor:getCurrentBuffer(), tbl, x, y)
end

local function applyMotionToContext(editor, toCtx, toDef)
	local defOptions = toDef[1]
	local defFunction = toDef[2]
	if defOptions then
		itertools.update(toCtx, defOptions)
	end
	toCtx = defFunction(editor, toCtx)
	return toCtx
end

local function applyOperator(editor, op, to)
	op(editor, to)
end

local emptyRegisterValue = {lines = {""}}

local makeMotionContext, finalizeMotion

local function evaluateTextObject(editor, toDef)
	local toCtx = makeMotionContext(editor)
	toCtx = applyMotionToContext(editor, toCtx, toDef)
	local to = finalizeMotion(editor, toCtx)
	return to
end

local function expandPaste(editor, opts)
	opts = opts or {}
	local str = editor.typeahead:getPasteData()
	for i = 1, safeencoding.len(str) do
		local ch = safeencoding.sub(str, i, i)
		if ch == "\n" or ch == "\r" then
			ch = "cr"
		end
		editor.typeahead:insert(ch, {index = i, noModeMap = opts.noModeMap, noLangMap = opts.noLangMap, update = opts.update, isPasted = true})
	end
end

function finalizeMotion(editor, toCtx)
	return toCtx
end

local function findCharacterInLine(editor, ch, toCtx, opts)
	opts = opts or {}
	toCtx = toCtx or makeMotionContext(editor)
	local buf = editor:getCurrentBuffer()
	if not buf then
		return nil
	end
	local line = buf:getLine(toCtx.y)
	if not line then
		return nil
	end
	local cache = buf:getScopedLineCache(toCtx.y, "characterPos")
	if cache == nil then
		cache = {}
		buf:setScopedLineCache(toCtx.y, "characterPos", cache)
	end
	local matches = cache[ch]
	if not matches then
		matches = strptn.findAll(line, ch)
		-- TODO lru eviction?
		cache[ch] = matches
	end
	local m = strptn.matchesGetAdjacent(matches, toCtx.x, 1, {backward = opts.backward or false, count = opts.count or 1})
	if not m then
		return nil
	end
	return m[1]
end

local getLineSearchMatches

local function findSearchStringInLine(editor, searchString, toCtx, opts)
	opts = opts or {}
	toCtx = toCtx or makeMotionContext(editor)
	local matches = getLineSearchMatches(editor, searchString, toCtx.y)
	if not matches then
		return nil
	end
	local key = 1
	if opts.patternEnd then
		key = 2
	end
	local m, remainingCount = strptn.matchesGetAdjacent(matches, toCtx.x, key, {backward = opts.backward or false, count = opts.count or 1})
	if not m then
		return nil, remainingCount
	end
	return m[key]
end

local function findSurroundingWordInLine(editor, toCtx, opts)
	opts = opts or {}
	toCtx = toCtx or makeMotionContext(editor)
	local buf = editor:getCurrentBuffer()
	if not buf then
		return nil
	end
	local line = buf:getLine(toCtx.y)
	if not line then
		return nil
	end
	local matches
	if opts.WORDs then
		matches = buf:getScopedLineCache(toCtx.y, "WORDs")
		if not matches then
			matches = strptn.findNonSpaceBoundaries(line)
			buf:setScopedLineCache(toCtx.y, "WORDs", matches)
		end
	else
		matches = buf:getScopedLineCache(toCtx.y, "words")
		if not matches then
			matches = strptn.findWordBoundaries(line)
			buf:setScopedLineCache(toCtx.y, "words", matches)
		end
	end
	return matches[strptn.matchesGetContainingIndex(matches, toCtx.x)]
end

local function findWordInLine(editor, toCtx, opts)
	opts = opts or {}
	toCtx = toCtx or makeMotionContext(editor)
	local buf = editor:getCurrentBuffer()
	if not buf then
		return nil
	end
	local line = buf:getLine(toCtx.y)
	if not line then
		return nil
	end
	local matches
	if opts.WORDs then
		matches = buf:getScopedLineCache(toCtx.y, "WORDs")
		if not matches then
			matches = strptn.findNonSpaceBoundaries(line)
			buf:setScopedLineCache(toCtx.y, "WORDs", matches)
		end
	else
		matches = buf:getScopedLineCache(toCtx.y, "words")
		if not matches then
			matches = strptn.findWordBoundaries(line)
			buf:setScopedLineCache(toCtx.y, "words", matches)
		end
	end
	local key = 1
	if opts.wordEnd then
		key = 2
	end
	local m, remainingCount = strptn.matchesGetAdjacent(matches, toCtx.x, key, {backward = opts.backward or false, count = opts.count or 1})
	if not m then
		return nil, remainingCount
	end
	return m[key]
end

local function getEffectiveStatusLineFormatString(editor)
	local fmt = editor.statusLineFormatString
	if not fmt or #fmt == 0 then
		-- Some of the items are not implemented and will be skipped
		fmt = "%<%f %h%m%r%=%-14.(%l,%c%V%) %P"
	end
	return fmt
end

function getLineSearchMatches(editor, searchString, y)
	local buf = editor:getCurrentBuffer()
	if not buf then
		return nil
	end
	local line = buf:getLine(y)
	if not line then
		return nil
	end
	local matches, cached
	cached = buf:getScopedLineCache(y, "searchResult")
	if not cached or cached.searchString ~= searchString then
		-- print("Find", searchString, "in", line); os.sleep(0.2)
		matches = strptn.findAll(line, searchString, {pattern = true})
		cached = {matches = matches, searchString = searchString}
		buf:setScopedLineCache(y, "searchResult", cached)
	else
		matches = cached.matches
	end
	return matches
end

local function getPasteDataAsRegister(editor)
	local str = editor.typeahead:getPasteData()
	local txt = strptn.splitBy(str, "\n")
	return {lines = txt}
end

local function getRegisterValueText(editor, regValue)
	return regValue.lines
end

local function getRepeatCount0(editor)
	return editor._repeatCount or 0
end

local function getRepeatCount1(editor)
	local num = getRepeatCount0(editor)
	if num == 0 then
		return 1
	end
	return num
end

local function getSearchBackward(editor)
	-- TODO better interface
	return editor._searchBackward or false
end

local function getSearchString(editor)
	-- TODO better interface
	return editor._searchString or ""
end

local function getSelectedRegister(editor)
	-- TODO registers
	return editor._unnamedRegister or emptyRegisterValue
end

local getTextObjectEnds

local function getTextObjectAsRegister(editor, to)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	local txt
	if to.linewise then
		-- Don't insert a leading/trailing line break like getTextObjectEnds does
		local begX, begY, edX, edY = to.initialX, to.initialY, to.x, to.y
		if begY > edY then
			begY, edY = edY, begY
		end
		txt = {}
		for y = begY, edY do
			table.insert(txt, buf:getLine(y))
		end
	else
		txt = buf:getTextBetween(getTextObjectEnds(editor, to))
		if txt == nil then
			return nil
		end
	end
	return {
		lines = txt,
		linewise = to.linewise,
	}
end

function getTextObjectEnds(editor, to)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	local begX, begY, edX, edY = to.initialX, to.initialY, to.x, to.y
	if to.empty and begY == edY and begX == edX + 1 then
		return begX, begY, edX, edY  -- TODO still check whether it is in-bounds
	end
	if edY < begY or edY == begY and edX < begX then
		begX, edX = edX, begX
		begY, edY = edY, begY
	end
	local lineCount = buf:getLineCount()
	local beforeSOB = false
	local afterEOB = false
	if begY < 1 then
		beforeSOB = true
		begY = 1
		begX = 1
	end
	if edY > lineCount then
		afterEOB = true
		edY = lineCount
	end
	local edLine = buf:getLine(edY)
	if afterEOB then
		edX = safeencoding.len(edLine)
		if to.exclusive then
			edX = edX + 1
		end
	end
	if to.linewise then
		if edY >= lineCount then
			if begY <= 1 then
				-- whole buffer
				return 1, 1, safeencoding.len(edLine), edY
			end
			begY = begY - 1
			local begLine = buf:getLine(begY)
			begX = safeencoding.len(begLine) + 1
			edX = safeencoding.len(edLine)
		else
			begX = 1
			edY = edY + 1
			edX = 0
		end
	elseif to.exclusive then
		edX = edX - 1
	end
	return begX, begY, edX, edY
end

local textObjects, registerValueFromText, updateCursorFromMotionContext, setTextObjectAsRegister, scrollToMotionContextEnd

local function insertTextAtCursor(editor, txt)
	local cursorToCtx = makeMotionContext(editor)
	if cursorToCtx == nil then
		return
	end
	cursorToCtx.exclusive = true
	local cursorTo = finalizeMotion(editor, cursorToCtx)
	local fakeRegValue = registerValueFromText(editor, txt)
	setTextObjectAsRegister(editor, cursorTo, fakeRegValue)
	if #txt == 1 then
		cursorToCtx.x = cursorToCtx.x + safeencoding.len(txt[1])
	else
		cursorToCtx.y = cursorToCtx.y + #txt - 1
		cursorToCtx.x = 1 + safeencoding.len(txt[#txt])
	end
	scrollToMotionContextEnd(editor, cursorToCtx)
	updateCursorFromMotionContext(editor, cursorToCtx)
end

local function isEmptyTextObject(editor, to)
	return to.empty
end

function makeMotionContext(editor)
	-- TODO cursor
	local toCtx = {
		initialX = editor._cursorX or 1,
		initialY = editor._cursorY or 1,
		wantX = editor._cursorWantX,
	}
	toCtx.x = toCtx.initialX
	toCtx.y = toCtx.initialY
	return toCtx
end

local function motionContextIntoBounds(editor, toCtx, opts)
	opts = opts or {}
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local lineCount = buf:getLineCount()
	if toCtx.y > lineCount then
		toCtx.y = lineCount
	end
	if toCtx.y < 1 then
		toCtx.y = 1
	end
	local line = buf:getLine(toCtx.y)
	local lineLength = safeencoding.len(line)
	if opts.onePastEnd then
		lineLength = lineLength + 1
	end
	if toCtx.x > lineLength then
		toCtx.x = lineLength
	end
	if toCtx.x < 1 then
		toCtx.x = 1
	end
end

local function performCursorMotion(editor, toDef, opts)
	local toCtx = makeMotionContext(editor)
	if toCtx == nil then
		return false
	end
	toCtx = applyMotionToContext(editor, toCtx, toDef)
	if toCtx == nil then
		return false
	end
	motionContextIntoBounds(editor, toCtx, opts)
	scrollToMotionContextEnd(editor, toCtx)
	updateCursorFromMotionContext(editor, toCtx)
	return true
end

local function performMouseMotion(editor, toCtx)
	local win = editor:getCurrentWindow()
	if win == nil then
		return
	end
	local inputProperties = editor.typeahead.inputProperties
	local mouseX, mouseY = inputProperties.mouseX, inputProperties.mouseY
	if not mouseX or not mouseY then
		return toCtx
	end
	toCtx.x, toCtx.y = win:unproject(mouseX, mouseY)
	toCtx.wantX = toCtx.x
	return toCtx
end

local function performSearchMotion(editor, toCtx, opts)
	opts = opts or {}
	local origX, origY = toCtx.x, toCtx.y
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local lineCount = buf:getLineCount()
	local repeatCount = getRepeatCount1(editor)
	local newX
	local yieldCounter = 0
	local searchString = getSearchString(editor)
	local backward = getSearchBackward(editor)
	if opts.previous then
		backward = not backward
	end
	while editor:isRunning() and toCtx.y >= 1 and toCtx.y <= lineCount do
		newX, repeatCount = findSearchStringInLine(editor, searchString, toCtx, {backward = backward, patternEnd = opts.patternEnd, count = repeatCount})
		if newX then
			toCtx.x = newX
			toCtx.wantX = nil
			return toCtx
		end
		if backward then
			toCtx.y = toCtx.y - 1
			toCtx.x = safeencoding.len(buf:getLine(toCtx.y) or "") + 1
		else
			toCtx.y = toCtx.y + 1
			toCtx.x = 0
		end
		yieldCounter = yieldCounter + 1
		if yieldCounter > 10 then
			yieldCounter = 0
			editor.typeahead:yieldCPU()
		end
	end
	local boundaryName = backward and "TOP" or "BOTTOM"
	editor:echoErr(("Search hit %s without match for: %s"):format(boundaryName, searchString))
	toCtx.x, toCtx.y = origX, origY
	return toCtx
end

local function performWordMotion(editor, toCtx, opts)
	opts = opts or {}
	local origX, origY = toCtx.x, toCtx.y
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local lineCount = buf:getLineCount()
	local repeatCount = getRepeatCount1(editor)
	local newX
	local yieldCounter = 0
	while editor:isRunning() and toCtx.y >= 1 and toCtx.y <= lineCount do
		newX, repeatCount = findWordInLine(editor, toCtx, {backward = opts.backward, wordEnd = opts.wordEnd, WORDs = opts.WORDs, count = repeatCount})
		if newX then
			toCtx.x = newX
			toCtx.wantX = nil
			return toCtx
		end
		if opts.backward then
			toCtx.y = toCtx.y - 1
			toCtx.x = safeencoding.len(buf:getLine(toCtx.y) or "") + 1
		else
			toCtx.y = toCtx.y + 1
			toCtx.x = 0
		end
		yieldCounter = yieldCounter + 1
		if yieldCounter > 10 then
			yieldCounter = 0
			editor.typeahead:yieldCPU()
		end
	end
	toCtx.x, toCtx.y = origX, origY
	return toCtx
end

local function populateStatusLineData(editor, win, fmt)
	if not editor or not win or type(fmt) ~= "string" then
		return nil
	end
	local buf = win.currentBuffer
	if not buf then
		return nil
	end
	local _, winHeight = win:getContentSize()
	local bufHeight = buf:getLineCount()
	local _, scrollY = win:getScrollAmount()
	local cursorToCtx = makeMotionContext(editor)
	local data = {}
	local cells = {""}
	local truncatePoint = {1, 0}
	local fmtStart = 1
	while fmtStart <= #fmt do
		local percentPos = fmt:find("%%", fmtStart) or #fmt + 1
		local literal = fmt:sub(fmtStart, percentPos - 1)
		fmtStart = percentPos
		cells[#cells] = cells[#cells] .. literal
		local ch
		local alignLeft, zeroPad, minWidth, maxWidth, stage = false, false, "", "", 1
		-- Parse format item
		while true do
			fmtStart = fmtStart + 1
			ch = fmt:sub(fmtStart, fmtStart)
			if #ch < 1 then
				break
			end
			if ch == "-" then
				if stage > 0 and stage <= 1 then
					alignLeft = true
					stage = 2
				else
					stage = -1
				end
			elseif ch == "0" and stage <= 2 then
				if stage > 0 then
					zeroPad = true
					stage = 3
				else
					stage = -1
				end
			elseif ch == "." then
				if stage > 0 and stage <= 3 then
					stage = 4
				else
					stage = -1
				end
			elseif ch:find("%d") then
				if stage > 0 and stage <= 3 then
					stage = 3
					minWidth = minWidth .. ch
				elseif stage == 4 then
					maxWidth = maxWidth .. ch
				else
					stage = -1
				end
			else
				break
			end
		end
		if #ch < 1 then
			break
		end
		if stage > 0 then
			fmtStart = fmtStart + 1
			local itemText, itemNumber = "", nil
			if ch == "<" then
				truncatePoint = {#cells, safeencoding.len(cells[#cells])}
			elseif ch == "f" then
				itemText = buf:getFilename() or "[No Name]"
			elseif ch == "=" then
				cells[#cells + 1] = ""
			elseif ch == "l" then
				itemNumber = cursorToCtx.y
			elseif ch == "c" then  -- in codepoints
				itemNumber = cursorToCtx.x
			elseif ch == "P" then
				local isTop = scrollY <= 0
				local isBot = scrollY + winHeight >= bufHeight
				if isTop and isBot then
					itemText = "All"
				elseif isTop then
					itemText = "Top"
				elseif isBot then
					itemText = "Bot"
				else
					local maxScroll = bufHeight - winHeight
					if maxScroll < 1 then
						maxScroll = 1
					end
					if scrollY >= maxScroll then
						scrollY = maxScroll - 1
					end
					local percents = math.floor(scrollY / maxScroll * 100)
					itemText = ("% 2d%%"):format(percents)
				end
			end
			if itemNumber then
				itemText = tostring(itemNumber)
				if #maxWidth > 0 then
					local n = tonumber(maxWidth)
					if n < 2 then
						n = 2
					end
					if n < #itemText then
						itemText = itemText:sub(1, n - 2) .. ">" .. tostring(#itemText - n + 2)
					end
				end
				if #minWidth > 0 then
					local n = tonumber(minWidth)
					if n > 50 then
						n = 50
					end
					local remainingLength = n - #itemText
					if remainingLength > 0 then
						local padChar = " "
						if zeroPad and not alignLeft then
							padChar = "0"
						end
						local padString = itertools.repeatString(padChar, remainingLength)
						if alignLeft then
							itemText = itemText .. padString
						else
							itemText = padString .. itemText
						end
					end
				end
			else
				if #maxWidth > 0 then
					local n = tonumber(maxWidth)
					if n < 1 then
						n = 1
					end
					local dropLength = safeencoding.len(itemText) - n + 1
					if dropLength > 1 then
						itemText = "<" .. safeencoding.sub(itemText, 1 + dropLength, dropLength + n - 1)
					end
				end
				if #minWidth > 0 then
					local n = tonumber(minWidth)
					if n > 50 then
						n = 50
					end
					local remainingLength = n - #itemText
					if remainingLength > 0 then
						itemText = itemText .. itertools.repeatString(" ", remainingLength)
					end
				end
			end
			cells[#cells] = cells[#cells] .. itemText
		end
	end
	data.cells = cells
	data.truncatePoint = truncatePoint
	return data
end

local function pullCountString(editor)
	editor.typeahead:applyModeMappings()
	local ch = editor.typeahead:peek()
	if ch:find("[^1-9]") then
		return ""
	end
	editor.typeahead:pull()
	local builder = {ch}
	while editor:isRunning() do
		ch = editor.typeahead:peek()
		if ch:find("%D") then
			return table.concat(builder)
		end
		editor.typeahead:pull()
		table.insert(builder, ch)
	end
	return nil
end

local function pullHexDigit(editor)
	local nibbleChar = typeahead.getSelfInsert(editor.typeahead:pull())
	if not nibbleChar:find("^[0-9A-Fa-f]$") then
		return nil
	end
	local nibbleNum
	if nibbleChar:find("[A-F]") then
		nibbleNum = nibbleChar:byte() - ("A"):byte() + 10
	elseif nibbleChar:find("[a-f]") then
		nibbleNum = nibbleChar:byte() - ("a"):byte() + 10
	else
		nibbleNum = nibbleChar:byte() - ("0"):byte()
	end
	return nibbleNum
end

local function pullInputCharacter(editor)
	editor.typeahead:applyModeMappings()
	editor.typeahead:applyLangMappings()
	local ch = typeahead.getSelfInsert(editor.typeahead:pull())
	if safeencoding.len(ch) ~= 1 then
		return nil
	end
	return ch
end

local runMode

local function pullSearchString(editor, backward)
	if modes == nil then
		modes = require("vim.modes")
	end
	local prompt = "/"
	if backward then
		prompt = "?"
	end
	local searchString = runMode(editor, modes.cmdline, {prompt = prompt, history = editor.searchHistory})
	if not searchString then
		return nil
	end
	if searchString:sub(1, 2) == "\\V" or searchString:sub(1, 2) == "\\M" then
		-- nomagic
		searchString = strptn.escapePtn(searchString:sub(3))
	end
	searchString = strptn.unescapeBackslash(searchString)
	local success, reason = strptn.validatePtn(searchString)
	if not success then
		editor:echoErr(("Invalid search string (%s): %s"):format(reason, searchString))
		return nil
	end
	return searchString
end

local function pullTextObject(editor)
	if modes == nil then
		modes = require("vim.modes")
	end
	local to = runMode(editor, modes.textObject)
	return to
end

local function pushModeCommandLine(editor)
	if modes == nil then
		modes = require("vim.modes")
	end
	if command == nil then
		command = require("vim.command")
	end
	local text = runMode(editor, modes.cmdline, {prompt = ":", history = editor.commandHistory})
	if text then
		command.execute(editor, text)
	end
	editor:render()
end

local function pushModeInsert(editor)
	if modes == nil then
		modes = require("vim.modes")
	end
	runMode(editor, modes.insertMode)
	performCursorMotion(editor, textObjects.characterBackward)
end

local function pushModeVisual(editor, toCtx)
	if modes == nil then
		modes = require("vim.modes")
	end
	runMode(editor, modes.visualMode, toCtx)
end

function registerValueFromText(editor, txt, protoRegValue)
	local regValue = {}
	if protoRegValue ~= nil then
		itertools.update(regValue, protoRegValue)
	end
	regValue.lines = itertools.collect(ipairs(txt))
	return regValue
end

local function restoreSelectionMotionContext(editor)
	-- TODO better interface & change scope
	if not editor._lastSelection then
		return makeMotionContext(editor)
	end
	return itertools.collect(pairs(editor._lastSelection))
end

runMode = function(editor, cb, ...)
	local oldModeMappings = editor.typeahead:getModeMappings()
	local oldLangMappings = editor.typeahead:getLangMappings()
	local oldModeMessagge = editor:getModeMessage()
	-- local result = table.pack(xpcall(cb, debug.traceback, editor, ...))
	local result = {true, cb(editor, ...)}
	editor.typeahead:setModeMappings(oldModeMappings)
	editor.typeahead:setLangMappings(oldLangMappings)
	editor:setModeMessage(oldModeMessagge)
	editor:render()
	if result[1] then
		return table.unpack(result, 2, result.n)
	else
		error(table.unpack(result, 2, result.n))
	end
end

local function scrollBy(editor, dx, dy, opts)
	local win = editor:getCurrentWindow()
	if win == nil then
		return
	end
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end
	local cursorToCtx = makeMotionContext(editor)
	if cursorToCtx == nil then
		return
	end

	local scrollX, scrollY = win:getScrollAmount()
	scrollX = scrollX + dx
	scrollY = scrollY + dy
	if scrollX < 0 then
		scrollX = 0
	end
	if scrollY < 0 then
		scrollY = 0
	end
	win:setScrollAmount(scrollX, scrollY)
	local contentWidth, contentHeight = win:getContentSize()
	local cursorWindowX, cursorWindowY = win:projectToContent(cursorToCtx.x, cursorToCtx.y)

	if cursorWindowX > contentWidth then
		cursorWindowX = contentWidth
		cursorToCtx.wantX = nil
	elseif cursorWindowX < 1 then
		cursorWindowX = 1
		cursorToCtx.wantX = nil
	end
	if cursorWindowY > contentHeight then
		cursorWindowY = contentHeight
	elseif cursorWindowY < 1 then
		cursorWindowY = 1
	end
	cursorToCtx.x, cursorToCtx.y = win:unprojectFromContent(cursorWindowX, cursorWindowY)

	motionContextIntoBounds(editor, cursorToCtx, opts)
	scrollToMotionContextEnd(editor, cursorToCtx)
	updateCursorFromMotionContext(editor, cursorToCtx)
end

function scrollToMotionContextEnd(editor, toCtx)
	local win = editor:getCurrentWindow()
	if win == nil then
		return
	end
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return
	end

	local scrollX, scrollY = win:getScrollAmount()
	local contentWidth, contentHeight = win:getContentSize()
	local cursorWindowX, cursorWindowY = win:projectToContent(toCtx.x, toCtx.y)
	if cursorWindowX > contentWidth then
		scrollX = scrollX + cursorWindowX - contentWidth
	elseif cursorWindowX < 1 then
		scrollX = scrollX + cursorWindowX - 1
	end
	if scrollX < 0 then
		scrollX = 0
	end
	if cursorWindowY > contentHeight then
		scrollY = scrollY + cursorWindowY - contentHeight
	elseif cursorWindowY < 1 then
		scrollY = scrollY + cursorWindowY - 1
	end
	if scrollY < 0 then
		scrollY = 0
	end

	win:setScrollAmount(scrollX, scrollY)
end

local function setLastSelection(editor, to)
	-- TODO better interface & change scope
	editor._lastSelection = to
end

local function setRepeatCount(editor, num)
	-- TODO better interface
	editor._repeatCount = num
end

local function setSearchBackward(editor, backward)
	-- TODO better interface
	editor._searchBackward = backward
end

local function setSearchString(editor, searchString)
	-- TODO better interface
	editor._searchString = searchString
end

local function setSelectedRegister(editor, regValue, opts)
	-- TODO registers
	editor._unnamedRegister = regValue
end

function setTextObjectAsRegister(editor, to, regValue)
	local buf = editor:getCurrentBuffer()
	if buf == nil then
		return nil
	end
	local txt = regValue.lines
	if regValue.linewise then
		txt = itertools.collect(ipairs(txt))
		local empty = isEmptyTextObject(editor, to)
		local after = empty and to.x > 0
		local numLines = buf:getLineCount()
		local eob = to.y >= numLines or to.initialY >= numLines
		local sob = to.y <= 1 or to.initialY <= 1
		if after or eob and not empty then
			if after or not sob then
				table.insert(txt, 1, "")
			end
		else
			table.insert(txt, "")
		end
	end
	buf:setTextBetween(txt, getTextObjectEnds(editor, to))
end

function updateCursorFromMotionContext(editor, toCtx)
	-- TODO cursor
	editor._cursorX = toCtx.x
	editor._cursorY = toCtx.y
	editor._cursorWantX = toCtx.wantX
end

textObjects = {
	characterForward = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.x = toCtx.x + getRepeatCount1(editor)
		local line = buf:getLine(toCtx.y)
		local lineLength = safeencoding.len(line)
		if toCtx.x > lineLength + 1 then
		    toCtx.x = lineLength + 1
		end
		toCtx.wantX = nil
		return toCtx
	end},
	characterBackward = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.x = toCtx.x - getRepeatCount1(editor)
		if toCtx.x < 1 then
			toCtx.x = 1
		end
		toCtx.wantX = nil
		return toCtx
	end},
	emptyForward = {{empty = true}, function(editor, toCtx)
		-- TODO consider using a simple exclusive motion with matching start and end instead
		toCtx.initialY = toCtx.y
		toCtx.initialX = toCtx.x + 1
		return toCtx
	end},
	emptyBackward = {{empty = true}, function(editor, toCtx)
		toCtx.y = toCtx.initialY
		toCtx.x = toCtx.initialX - 1
		return toCtx
	end},
	eol = {{exclusive = false}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.y = toCtx.y + getRepeatCount1(editor) - 1
		local numLines = buf:getLineCount()
		if toCtx.y > numLines then
		    toCtx.y = numLines
		end
		local line = buf:getLine(toCtx.y)
		local lineLength = safeencoding.len(line)
		toCtx.x = lineLength + 1
		toCtx.wantX = nil
		return toCtx
	end},
	sol = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.y = toCtx.y - getRepeatCount1(editor) + 1  -- It is not possible to provide count to "0"
		if toCtx.y < 1 then
			toCtx.y = 1
		end
		toCtx.x = 1
		toCtx.wantX = nil
		return toCtx
	end},
	solNonSpace = {{exclusive = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		toCtx.y = toCtx.y - getRepeatCount1(editor) + 1  -- Real Vim doesn't accept count for "^"
		if toCtx.y < 1 then
			toCtx.y = 1
		end
		local line = buf:getLine(toCtx.y)
		toCtx.x = strptn.firstNonSpace(line) or safeencoding.len(line) + 1
		toCtx.wantX = nil
		return toCtx
	end},
	line = {{linewise = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if toCtx.wantX ~= nil then
		    toCtx.x = toCtx.wantX
		else
		    toCtx.wantX = toCtx.x
		end
		toCtx.y = toCtx.y + getRepeatCount1(editor) - 1
		local numLines = buf:getLineCount()
		if toCtx.y > numLines then
		    toCtx.y = numLines
		end
		local line = buf:getLine(toCtx.y)
		local lineLength = safeencoding.len(line)
		if toCtx.x > lineLength + 1 then  -- do we need "lineLength + 1" in any text objects?
		    toCtx.x = lineLength + 1
		end
		return toCtx
	end},
	--- Same as line, but selects at least 2 lines (unless at the last line in the buffer)
	multipleLines = {{linewise = true}, function(editor, toCtx)
		local buf = editor:getCurrentBuffer()
		if buf == nil then
			return
		end
		if toCtx.wantX ~= nil then
		    toCtx.x = toCtx.wantX
		else
		    toCtx.wantX = toCtx.x
		end
		local count = getRepeatCount1(editor)
		if count < 2 then
			count = 2
		end
		toCtx.y = toCtx.y + count - 1
		local numLines = buf:getLineCount()
		if toCtx.y > numLines then
		    toCtx.y = numLines
		end
		local line = buf:getLine(toCtx.y)
		local lineLength = safeencoding.len(line)
		if toCtx.x > lineLength + 1 then  -- do we need "lineLength + 1" in any text objects?
		    toCtx.x = lineLength + 1
		end
		return toCtx
	end},
	searchNext = {{exclusive = true}, function(editor, toCtx)
		editor.hlsearch = editor.triggerHlsearch
		editor:invalidateDisplay()
		return performSearchMotion(editor, toCtx, {previous = false})
	end},
	searchPrevious = {{exclusive = true}, function(editor, toCtx)
		editor.hlsearch = editor.triggerHlsearch
		editor:invalidateDisplay()
		return performSearchMotion(editor, toCtx, {previous = true})
	end},
}

return {
	appendTextAtBuffer = appendTextAtBuffer,
	appendTextAt = appendTextAt,
	applyMotionToContext = applyMotionToContext,
	applyOperator = applyOperator,
	emptyRegisterValue = emptyRegisterValue,
	evaluateTextObject = evaluateTextObject,
	expandPaste = expandPaste,
	finalizeMotion = finalizeMotion,
	findCharacterInLine = findCharacterInLine,
	findSearchStringInLine = findSearchStringInLine,
	findSurroundingWordInLine = findSurroundingWordInLine,
	findWordInLine = findWordInLine,
	getEffectiveStatusLineFormatString = getEffectiveStatusLineFormatString,
	getLineSearchMatches = getLineSearchMatches,
	getPasteDataAsRegister = getPasteDataAsRegister,
	getRegisterValueText = getRegisterValueText,
	getRepeatCount0 = getRepeatCount0,
	getRepeatCount1 = getRepeatCount1,
	getSearchBackward = getSearchBackward,
	getSearchString = getSearchString,
	getSelectedRegister = getSelectedRegister,
	getTextObjectAsRegister = getTextObjectAsRegister,
	getTextObjectEnds = getTextObjectEnds,
	insertTextAtCursor = insertTextAtCursor,
	isEmptyTextObject = isEmptyTextObject,
	makeMotionContext = makeMotionContext,
	motionContextIntoBounds = motionContextIntoBounds,
	performCursorMotion = performCursorMotion,
	performMouseMotion = performMouseMotion,
	performSearchMotion = performSearchMotion,
	performWordMotion = performWordMotion,
	populateStatusLineData = populateStatusLineData,
	pullCountString = pullCountString,
	pullHexDigit = pullHexDigit,
	pullInputCharacter = pullInputCharacter,
	pullSearchString = pullSearchString,
	pullTextObject = pullTextObject,
	pushModeCommandLine = pushModeCommandLine,
	pushModeInsert = pushModeInsert,
	pushModeVisual = pushModeVisual,
	registerValueFromText = registerValueFromText,
	restoreSelectionMotionContext = restoreSelectionMotionContext,
	runMode = runMode,
	scrollBy = scrollBy,
	scrollToMotionContextEnd = scrollToMotionContextEnd,
	setLastSelection = setLastSelection,
	setRepeatCount = setRepeatCount,
	setSearchBackward = setSearchBackward,
	setSearchString = setSearchString,
	setSelectedRegister = setSelectedRegister,
	setTextObjectAsRegister = setTextObjectAsRegister,
	textObjects = textObjects,
	updateCursorFromMotionContext = updateCursorFromMotionContext,
}
